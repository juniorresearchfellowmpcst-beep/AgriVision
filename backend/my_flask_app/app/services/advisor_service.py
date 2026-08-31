"""Service layer for the crop advisor.

Wraps :mod:`app.ai.gemini_advisor` in the ``(response, status)`` shape the rest
of the API uses, and resolves the two ways the app can point at an image:

  * it uploads one (the leaf photo the farmer just took, or a frame they picked
    out of a survey), or
  * it names a stored capture frame or scan by id, and the server reads it off
    disk -- which is what "More information" does from a survey summary, where
    the picture is already on the ground station and re-uploading it over a
    field connection would be a slow way to send something the server has.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Optional, Tuple

from app.ai import gemini_advisor
from app.ai.gemini_advisor import AdvisorError
from app.repositories.capture_repository import CaptureFrameRepository
from app.repositories.disease_scan_repository import DiseaseScanRepository
from app.repositories.field_scan_repository import FieldScanRepository
from app.repositories.survey_repository import SurveyRepository

logger = logging.getLogger(__name__)

MAX_HISTORY_TURNS = 12


def _fail(message: str, status: int = 400) -> Tuple[Dict[str, Any], int]:
    return {"status": "error", "message": message}, status


class AdvisorService:

    @staticmethod
    def capabilities() -> Tuple[Dict[str, Any], int]:
        return {"status": "ok", **gemini_advisor.capabilities()}, 200

    @staticmethod
    def ask(
        question: str,
        image_bytes: Optional[bytes] = None,
        mime_type: str = "image/jpeg",
        context: Optional[Dict[str, Any]] = None,
        history: Optional[List[Dict[str, str]]] = None,
        capture_base: Optional[str] = None,
        frame_id: Optional[int] = None,
        scan_id: Optional[int] = None,
        disease_scan_id: Optional[int] = None,
        run_id: Optional[int] = None,
        user_id: Optional[int] = None,
        language: Optional[str] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Answer one question about one scan.

        Everything except ``question`` is optional: the advisor is useful with
        a photo and no diagnosis, with a diagnosis and no photo, and (least
        usefully, but still) with neither.
        """
        scan_context: Dict[str, Any] = dict(context or {})

        # Pull the picture and the diagnosis off the server where we can, so
        # the app does not have to re-upload something already stored.
        if image_bytes is None and frame_id is not None and capture_base:
            image_bytes, error = AdvisorService._frame_bytes(
                frame_id, capture_base, user_id
            )
            if error:
                return error

        if scan_id is not None:
            record = FieldScanRepository.get_by_id(scan_id)
            if record is not None:
                scan_context.setdefault("crop", record.crop)
                scan_context.setdefault("field_name", record.field_name)
                # The stored detail carries the full scan; prefer it, and fall
                # back to the flat columns when the row predates it.
                detail = record.detail_dict()
                for key in ("disease", "severity", "weeds", "crop_name"):
                    if detail.get(key) is not None:
                        scan_context.setdefault(key, detail[key])
                scan_context.setdefault(
                    "disease",
                    {
                        "name": record.condition_name,
                        "confidence": record.confidence,
                        "source": record.engine,
                    },
                )

        if disease_scan_id is not None:
            record = DiseaseScanRepository.get_by_id(disease_scan_id)
            if record is not None:
                scan_context.setdefault(
                    "disease",
                    {
                        "name": record.condition_name,
                        "confidence": record.confidence,
                        "source": record.engine,
                    },
                )
                scan_context.setdefault(
                    "severity", {"level": record.severity}
                )
                scan_context.setdefault("field_name", record.field_name)

        if run_id is not None:
            run = SurveyRepository.get_by_id(run_id)
            if run is not None and (
                run.user_id is None or user_id is None or run.user_id == user_id
            ):
                summary = run.summary_dict()
                scan_context.setdefault("crop", run.crop)
                scan_context.setdefault("field_name", run.field_name)
                scan_summary = summary.get("scan") or {}
                if scan_summary.get("conditions"):
                    scan_context.setdefault("conditions", scan_summary["conditions"])
                if scan_summary.get("weed"):
                    scan_context.setdefault(
                        "weeds", {"pressure": scan_summary["weed"]}
                    )

        cleaned_history = AdvisorService._clean_history(history)

        try:
            answer = gemini_advisor.ask(
                question=question,
                context=gemini_advisor.build_context(scan_context),
                image_bytes=image_bytes,
                mime_type=mime_type,
                history=cleaned_history,
                language=language,
            )
        except AdvisorError as exc:
            return _fail(str(exc), exc.status)
        except Exception as exc:  # pragma: no cover - defensive
            logger.exception("Crop advisor failed")
            return _fail(f"The crop advisor failed: {exc}", 500)

        return {
            "status": "ok",
            "question": question,
            "had_image": image_bytes is not None,
            **answer,
        }, 200

    @staticmethod
    def suggestions(
        context: Optional[Dict[str, Any]] = None,
        language: Optional[str] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Opening questions, so the chat does not start on an empty box.

        These stay in English even when the advisor will answer in Hindi:
        they are built from the app's own condition names, which come from the
        knowledge base in English, and machine-translating them here would
        produce worse Hindi than the model writes itself.
        """
        return {
            "status": "ok",
            "questions": gemini_advisor.suggested_questions(context),
            "language": language,
            **gemini_advisor.capabilities(),
        }, 200

    # -- helpers -----------------------------------------------------------

    @staticmethod
    def _frame_bytes(frame_id: int, capture_base: str, user_id: Optional[int]):
        frame = CaptureFrameRepository.get_by_id(frame_id)
        if frame is None:
            return None, _fail("No such capture frame.", 404)
        if frame.user_id is not None and user_id is not None and frame.user_id != user_id:
            return None, _fail("Not your capture.", 403)

        path = os.path.join(capture_base, frame.path.replace("/", os.sep))
        if not os.path.isfile(path):
            return None, _fail(
                "That frame is recorded but its file is missing from the "
                "server. Attach the photo instead.",
                410,
            )
        try:
            with open(path, "rb") as handle:
                return handle.read(), None
        except OSError as exc:
            return None, _fail(f"Could not read that frame: {exc}", 500)

    @staticmethod
    def _clean_history(history: Optional[List[Any]]) -> List[Dict[str, str]]:
        """Trim and normalise the conversation the app sent back.

        Capped because the whole history is re-sent on every turn: an
        afternoon's chat would otherwise grow into a slow, expensive request
        over exactly the connection least able to carry it.
        """
        if not isinstance(history, list):
            return []
        cleaned: List[Dict[str, str]] = []
        for turn in history[-MAX_HISTORY_TURNS:]:
            if not isinstance(turn, dict):
                continue
            text = str(turn.get("text") or turn.get("message") or "").strip()
            if not text:
                continue
            role = str(turn.get("role") or "user").lower()
            cleaned.append({
                "role": "model" if role in ("model", "assistant", "advisor") else "user",
                "text": text[:4000],
            })
        return cleaned
