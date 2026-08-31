"""The "More information" button: a photo and a diagnosis, sent to Gemini.

The on-board detectors answer a narrow question well -- *is this canopy sick,
and with what, out of the conditions this crop gets in Madhya Pradesh*. They
cannot answer the questions a farmer actually asks next: is it safe to spray
this at flowering, my neighbour had this last year and lost the crop, what does
it look like in three days, can I use what is left in the shed instead.

Those are open-ended, and the honest way to answer them is to hand the picture
and everything already known about it to a general model and let the farmer
keep asking. That is all this module is: a thin, well-labelled client.

Design notes worth keeping:

  * **The local diagnosis goes in the prompt.** Gemini is asked to build on the
    CNN's answer, not to silently replace it -- and where it disagrees, it is
    asked to say so, because a farmer seeing two different disease names with
    no explanation is worse off than before they asked.
  * **No key means a clear 503, not a fake answer.** An advisor that invents a
    plausible reply when it is not configured is the single worst failure mode
    available here.
  * **History is passed in by the caller.** Nothing is stored in this module;
    the conversation lives in the request, so two operators asking about two
    fields cannot bleed into each other.
"""

from __future__ import annotations

import base64
import logging
import os
import time
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

API_ROOT = "https://generativelanguage.googleapis.com/v1beta/models"

# Flash is the right default here: the question is usually a follow-up on a
# photo, the operator is on a field connection, and latency matters more than
# the last few points of reasoning quality.
#
# The *alias*, not a pinned version, and that is deliberate. A pinned model id
# rots: `gemini-2.5-flash` was this default until Google retired it for new
# keys, and the whole feature answered 404 on a ground station nobody was
# watching. `-latest` follows whatever the current flash model is, and an
# operator who needs a specific version can still pin one with GEMINI_MODEL.
DEFAULT_MODEL = "gemini-flash-latest"

# A field radio link is slow, and an operator standing in the sun will not wait
# two minutes. Fail with a clear message instead of hanging the screen.
REQUEST_TIMEOUT_S = 45

MAX_IMAGE_BYTES = 8 * 1024 * 1024

# Google's flash models answer 503 UNAVAILABLE ("currently experiencing high
# demand") often enough that a single attempt is not a fair test of whether the
# advisor works -- in testing, the third try succeeded within four seconds. An
# operator standing in a field should not have to decide whether to tap again.
#
# Only the transient statuses are retried. A wrong key or a retired model will
# answer the same way forever, and retrying those just makes the error slower.
RETRY_STATUSES = (429, 500, 502, 503, 504)
MAX_ATTEMPTS = 3
RETRY_BACKOFF_S = (1.0, 2.5)   # waits between attempts; total stays well under
                               # REQUEST_TIMEOUT_S so the screen is never stuck

# What the model is told it is. Written to keep the answer usable by somebody
# standing in a field, and to stop it drifting into a chemical prescription
# that outranks the label on the container.
SYSTEM_PROMPT = """You are an agricultural advisor helping a farmer in Madhya \
Pradesh, India, who is using a drone-based crop scouting app called AgriVision.

You are being shown a photograph from the field together with a diagnosis \
already produced by the app's own CNN model. Your job is to help the farmer \
understand and act on it.

Rules:
- Build on the app's diagnosis. If you think it is wrong, say so plainly and \
explain what you see instead -- do not quietly substitute a different answer.
- Be specific to Indian smallholder farming: local crop names, products \
available at an Indian agri-dealer, and doses per acre.
- Never present a chemical recommendation as final. The product label and the \
local KVK (Krishi Vigyan Kendra) outrank you, and you should say so once.
- If the photo is too blurred, too far away, or does not show a crop, say that \
rather than guessing.
- Answer in short paragraphs or short bullets. This is being read on a phone \
in the sun, not on a desk.
- Answer in the language the farmer writes in. If they write in Hindi or \
Hinglish, reply the same way.
"""


class AdvisorError(RuntimeError):
    """The advisor could not answer, with a message worth showing an operator."""

    def __init__(self, message: str, status: int = 502):
        super().__init__(message)
        self.status = status


def api_key() -> Optional[str]:
    """The configured key, or None. Both spellings are accepted because the
    Google SDKs themselves disagree about which one is canonical."""
    for name in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        value = (os.environ.get(name) or "").strip()
        if value:
            return value
    return None


def model_name() -> str:
    return (os.environ.get("GEMINI_MODEL") or "").strip() or DEFAULT_MODEL


def is_configured() -> bool:
    return api_key() is not None


def capabilities() -> Dict[str, Any]:
    """What the app should offer, checked before the button is shown."""
    configured = is_configured()
    return {
        "available": configured,
        "model": model_name() if configured else None,
        "accepts_images": True,
        "message": (
            "Ask the crop advisor about a scan."
            if configured
            else "The crop advisor is not configured on this server. Set "
                 "GEMINI_API_KEY in the backend's .env to enable it."
        ),
    }


def build_context(scan: Optional[Dict[str, Any]]) -> str:
    """Turn a scan result into the paragraph that precedes the farmer's question.

    Only what the app is reasonably sure of goes in. Padding the prompt with
    every field of the scan buries the diagnosis the model is meant to build on.
    """
    if not isinstance(scan, dict) or not scan:
        return "No automated diagnosis is attached to this photo."

    lines: List[str] = []

    crop = scan.get("crop_name") or scan.get("crop")
    if crop:
        lines.append(f"Crop: {crop}")

    disease = scan.get("disease") or {}
    if disease.get("name"):
        confidence = disease.get("confidence")
        source = disease.get("source")
        detail = f"App's diagnosis: {disease['name']}"
        if confidence is not None:
            try:
                detail += f" (confidence {float(confidence):.0%}"
                detail += f", from the {source} engine)" if source else ")"
            except (TypeError, ValueError):
                detail += ")"
        lines.append(detail)

    severity = (scan.get("severity") or {}).get("level")
    if severity:
        lines.append(f"Severity the app estimated: {severity}")

    weeds = scan.get("weeds") or {}
    pressure = (weeds.get("pressure") or {}).get("level")
    if pressure:
        percent = (weeds.get("pressure") or {}).get("percent")
        lines.append(
            f"Weed pressure: {pressure}"
            + (f" ({percent}% ground cover)" if percent is not None else "")
        )

    if scan.get("field_name"):
        lines.append(f"Block: {scan['field_name']}")
    if scan.get("lat") is not None and scan.get("lon") is not None:
        lines.append(f"Location: {scan['lat']:.5f}, {scan['lon']:.5f}")

    conditions = scan.get("conditions")
    if isinstance(conditions, list) and conditions:
        named = ", ".join(
            f"{c.get('name')} ({int(round(float(c.get('frame_share') or 0) * 100))}% "
            "of frames)"
            for c in conditions[:4]
            if isinstance(c, dict) and c.get("name")
        )
        if named:
            lines.append(f"Across the survey pass: {named}")

    if not lines:
        return "No automated diagnosis is attached to this photo."
    return "What the app already found:\n" + "\n".join(f"- {line}" for line in lines)


def _parts_for(
    question: str,
    context: str,
    image_bytes: Optional[bytes],
    mime_type: str,
) -> List[Dict[str, Any]]:
    parts: List[Dict[str, Any]] = []
    if image_bytes:
        parts.append({
            "inline_data": {
                "mime_type": mime_type or "image/jpeg",
                "data": base64.b64encode(image_bytes).decode("ascii"),
            }
        })
    text = context.strip()
    text = f"{text}\n\nFarmer's question: {question.strip()}" if text else question.strip()
    parts.append({"text": text})
    return parts


def ask(
    question: str,
    context: str = "",
    image_bytes: Optional[bytes] = None,
    mime_type: str = "image/jpeg",
    history: Optional[List[Dict[str, str]]] = None,
) -> Dict[str, Any]:
    """Ask the advisor one question, optionally about one photo.

    ``history`` is a list of ``{"role": "user"|"model", "text": "..."}`` from
    earlier in the same conversation, so a follow-up ("and if it rains
    tomorrow?") is answered in context. Raises :class:`AdvisorError` with a
    message meant for the operator, never a bare stack trace.
    """
    question = (question or "").strip()
    if not question:
        raise AdvisorError("Ask a question about the scan.", 400)

    key = api_key()
    if not key:
        raise AdvisorError(
            "The crop advisor is not configured on this server. Add "
            "GEMINI_API_KEY to the backend's .env and restart it.",
            503,
        )

    if image_bytes and len(image_bytes) > MAX_IMAGE_BYTES:
        raise AdvisorError(
            f"That photo is {len(image_bytes) // (1024 * 1024)} MB, over the "
            f"{MAX_IMAGE_BYTES // (1024 * 1024)} MB the advisor accepts. Take "
            "it again at a lower resolution.",
            400,
        )

    try:
        import requests
    except ImportError:  # pragma: no cover - requests is a hard dependency
        raise AdvisorError("The 'requests' package is missing on the server.", 503)

    contents: List[Dict[str, Any]] = []
    for turn in history or []:
        if not isinstance(turn, dict):
            continue
        text = str(turn.get("text") or "").strip()
        if not text:
            continue
        role = "model" if str(turn.get("role")) == "model" else "user"
        contents.append({"role": role, "parts": [{"text": text}]})

    contents.append({
        "role": "user",
        "parts": _parts_for(question, context, image_bytes, mime_type),
    })

    payload = {
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": contents,
        "generationConfig": {
            "temperature": 0.4,          # advice, not creative writing
            "maxOutputTokens": 1200,
        },
    }

    url = f"{API_ROOT}/{model_name()}:generateContent"
    response = None

    for attempt in range(MAX_ATTEMPTS):
        try:
            response = requests.post(
                url,
                # The key goes in a header, not in `?key=`. Query strings end
                # up in proxy logs, crash reports and browser history; a header
                # does not. Both forms authenticate, so there is no reason to
                # use the leaky one.
                headers={"X-goog-api-key": key, "Content-Type": "application/json"},
                json=payload,
                timeout=REQUEST_TIMEOUT_S,
            )
        except Exception as exc:
            logger.warning("Gemini request failed: %s", exc)
            raise AdvisorError(
                "Could not reach the crop advisor. Check that the ground "
                "station has internet -- this is the one feature that needs it.",
                502,
            )

        if response.status_code not in RETRY_STATUSES:
            break
        if attempt == MAX_ATTEMPTS - 1:
            break

        # Honour a Retry-After when Google sends one, but never wait longer
        # than the backoff schedule: a 60-second hint is a reason to give up
        # and tell the operator, not to freeze the screen for a minute.
        wait = RETRY_BACKOFF_S[attempt]
        try:
            hinted = float(response.headers.get("Retry-After", 0))
            wait = min(max(wait, hinted), RETRY_BACKOFF_S[-1])
        except (TypeError, ValueError):
            pass
        logger.info(
            "Gemini answered %s; retrying in %.1fs (attempt %s/%s)",
            response.status_code, wait, attempt + 2, MAX_ATTEMPTS,
        )
        time.sleep(wait)

    if response.status_code == 400:
        raise AdvisorError(
            "The crop advisor rejected the request. The API key may be wrong "
            "or the photo may be in a format it cannot read.",
            502,
        )
    if response.status_code in (401, 403):
        raise AdvisorError(
            "The crop advisor refused the API key configured on this server.",
            502,
        )
    if response.status_code == 404:
        # Almost always a retired model id rather than a bad URL. Google's own
        # message names the replacement, so pass it through instead of burying
        # it — this is the one failure an admin can fix in one env var.
        detail = _error_message(response)
        raise AdvisorError(
            f"The configured model '{model_name()}' is not available to this "
            "API key. Set GEMINI_MODEL in the backend's .env to a current one "
            "(or unset it to use the default alias)."
            + (f" Google said: {detail}" if detail else ""),
            502,
        )
    if response.status_code == 429:
        raise AdvisorError(
            "The crop advisor is rate-limited right now. Try again in a minute.",
            429,
        )
    if response.status_code >= 500:
        # Already retried above, so this is a spike that outlasted the backoff.
        raise AdvisorError(
            "The crop advisor is busy at its end -- this usually clears in a "
            "minute. Everything else in the app works meanwhile.",
            502,
        )
    if response.status_code != 200:
        raise AdvisorError(
            f"The crop advisor answered {response.status_code}.", 502
        )

    try:
        data = response.json()
    except ValueError:
        raise AdvisorError("The crop advisor sent a reply that could not be read.", 502)

    answer, finish_reason = _extract_text(data)
    if not answer:
        if finish_reason == "SAFETY":
            raise AdvisorError(
                "The advisor declined to answer that. Try rephrasing the "
                "question around the crop and the symptom.",
                422,
            )
        raise AdvisorError("The crop advisor returned an empty answer.", 502)

    usage = data.get("usageMetadata") or {}
    return {
        "answer": answer,
        "model": model_name(),
        "finish_reason": finish_reason,
        "tokens": {
            "prompt": usage.get("promptTokenCount"),
            "answer": usage.get("candidatesTokenCount"),
            "total": usage.get("totalTokenCount"),
        },
    }


def _error_message(response) -> str:
    """Google's own explanation for a failed call, when it sent one."""
    try:
        return str((response.json().get("error") or {}).get("message") or "")
    except Exception:
        return ""


def _extract_text(data: Dict[str, Any]) -> Tuple[str, Optional[str]]:
    candidates = data.get("candidates") or []
    if not candidates:
        # A prompt blocked before generation reports itself here rather than in
        # candidates, and the reason is worth passing on.
        feedback = (data.get("promptFeedback") or {}).get("blockReason")
        return "", feedback

    candidate = candidates[0]
    parts = (candidate.get("content") or {}).get("parts") or []
    text = "".join(part.get("text", "") for part in parts if isinstance(part, dict))
    return text.strip(), candidate.get("finishReason")


def suggested_questions(scan: Optional[Dict[str, Any]] = None) -> List[str]:
    """Starter questions, so the chat does not open on a blank box.

    Tailored to what was actually found: asking "how do I treat this" about a
    healthy canopy wastes the farmer's first tap.
    """
    disease = (scan or {}).get("disease") or {}
    name = disease.get("name")
    weeds = ((scan or {}).get("weeds") or {}).get("pressure") or {}

    if name and name != "No disease detected":
        return [
            f"How serious is {name} at this stage?",
            f"What should I spray for {name}, and when?",
            "Is it safe to spray this while the crop is flowering?",
            "How do I stop it spreading to the rest of the field?",
        ]
    if weeds.get("level") in ("moderate", "high"):
        return [
            "Which weeds are these, and how much yield will they cost me?",
            "Is a herbicide worth it at this stage, or should I hand-weed?",
            "What can I do to stop this coming back next season?",
        ]
    return [
        "Does this crop look healthy to you?",
        "What should I be watching for at this stage?",
        "When should I fly the next survey?",
    ]
