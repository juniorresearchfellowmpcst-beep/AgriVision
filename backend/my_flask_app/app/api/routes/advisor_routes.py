"""HTTP routes for the crop advisor -- the "More information" button.

Thin controllers over :class:`app.services.advisor_service.AdvisorService`.

    GET  /api/advisor/health       is the advisor configured on this server?
    POST /api/advisor/suggest      opening questions for a given scan
    POST /api/advisor/ask          ask about a photo and a diagnosis

``/ask`` accepts either multipart (the app attaches the photo) or JSON (the
app names a frame or scan the server already holds). Both carry the same
optional fields, so the app does not have to choose a shape based on where the
picture happens to be.
"""

import json
import os

from flask import Blueprint, current_app, jsonify, request

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.advisor_service import AdvisorService

advisor_bp = Blueprint("advisor", __name__)

_CAPTURE_SUBDIR = "captures"


def _capture_base() -> str:
    path = os.path.join(current_app.instance_path, _CAPTURE_SUBDIR)
    os.makedirs(path, exist_ok=True)
    return path


def _first_upload():
    """(bytes, mime) for the first non-empty file part, field-name agnostic."""
    for _field, storage in request.files.items(multi=True):
        data = storage.read()
        if data:
            return data, (storage.mimetype or "image/jpeg")
    return None, "image/jpeg"


def _maybe_json(raw):
    """Parse a JSON string sent as a multipart form field.

    Multipart cannot nest, so the app sends the diagnosis and the conversation
    history as JSON strings. A malformed one is treated as absent rather than
    failing the request -- the advisor is still useful with a photo and no
    context, and a farmer waiting on an answer should not get a 400 because a
    context field they never saw was badly encoded.
    """
    if not raw:
        return None
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        return None


def _int_or_none(value):
    try:
        return int(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


@advisor_bp.route("/health", methods=["GET"])
def health():
    """Whether the advisor is configured. The app hides the button if not."""
    response, status = AdvisorService.capabilities()
    return jsonify(response), status


@advisor_bp.route("/suggest", methods=["POST"])
def suggest():
    """Starter questions tailored to what the scan found."""
    payload = request.get_json(silent=True) or {}
    response, status = AdvisorService.suggestions(
        payload.get("context"), language=payload.get("language")
    )
    return jsonify(response), status


@advisor_bp.route("/ask", methods=["POST"])
@jwt_optional_lenient
def ask():
    """Ask the advisor about a scan.

    Multipart: an image part (any field name) plus form fields ``question``,
    ``context`` (JSON), ``history`` (JSON), ``frame_id``, ``scan_id``,
    ``disease_scan_id``, ``run_id``.

    JSON: the same fields, with no image -- the server reads the picture from
    whichever id was named.
    """
    if request.files:
        image_bytes, mime_type = _first_upload()
        form = request.form
        question = form.get("question", "")
        context = _maybe_json(form.get("context"))
        history = _maybe_json(form.get("history"))
        language = form.get("language") or None
        ids = {
            "frame_id": _int_or_none(form.get("frame_id")),
            "scan_id": _int_or_none(form.get("scan_id")),
            "disease_scan_id": _int_or_none(form.get("disease_scan_id")),
            "run_id": _int_or_none(form.get("run_id")),
        }
    else:
        payload = request.get_json(silent=True) or {}
        image_bytes, mime_type = None, "image/jpeg"
        question = payload.get("question", "")
        context = payload.get("context")
        history = payload.get("history")
        language = payload.get("language") or None
        ids = {
            "frame_id": _int_or_none(payload.get("frame_id")),
            "scan_id": _int_or_none(payload.get("scan_id")),
            "disease_scan_id": _int_or_none(payload.get("disease_scan_id")),
            "run_id": _int_or_none(payload.get("run_id")),
        }

    response, status = AdvisorService.ask(
        question=question,
        image_bytes=image_bytes,
        mime_type=mime_type,
        context=context if isinstance(context, dict) else None,
        history=history if isinstance(history, list) else None,
        capture_base=_capture_base(),
        user_id=current_user_id(),
        language=language,
        **ids,
    )
    return jsonify(response), status
