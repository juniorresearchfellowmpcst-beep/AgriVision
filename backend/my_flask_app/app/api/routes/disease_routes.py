"""HTTP routes for plant-leaf disease identification.

Thin controllers over :class:`app.services.disease_service.DiseaseService`,
mirroring the other route modules. The endpoints are open (no login required)
so the app can offer disease scanning to anonymous users, exactly like the
multispectral analyzer.

    GET  /api/disease/health     -> module capabilities
    POST /api/disease/identify   -> multipart photo in -> diagnosis + solution
    GET  /api/disease/scans      -> past scans (history)
    GET  /api/disease/scans/<id> -> one past scan with its full diagnosis
"""

from flask import Blueprint, jsonify, request

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.disease_service import DiseaseService

disease_bp = Blueprint("disease", __name__)


def _first_upload() -> tuple:
    """Return (bytes, filename) for the first non-empty uploaded file part.

    Field-name agnostic so the app can post under 'image', 'file', 'photo',
    etc. Returns (None, None) when nothing usable was attached.
    """
    for _field_name, storage in request.files.items(multi=True):
        data = storage.read()
        if data:
            return data, storage.filename
    return None, None


@disease_bp.route("/health", methods=["GET"])
def health():
    """Report the module's capabilities and active engine (model/heuristic)."""
    response, status = DiseaseService.capabilities()
    return jsonify(response), status


@disease_bp.route("/identify", methods=["POST"])
@jwt_optional_lenient
def identify():
    """Identify the disease in an uploaded leaf photo and return a solution.

    Multipart form-data with a single image file part (any field name). Returns
    the condition name, severity, symptoms, causes, treatment solutions and
    prevention tips, and records the scan in history.
    """
    image_bytes, filename = _first_upload()
    if image_bytes is None:
        return jsonify({
            "status": "error",
            "message": "Attach a photo of the plant leaf (multipart file part).",
        }), 400

    response, status = DiseaseService.identify(
        image_bytes,
        filename=filename,
        user_id=current_user_id(),
        field_name=(request.form.get("field_name") or None),
    )
    return jsonify(response), status


@disease_bp.route("/scans", methods=["GET"])
@jwt_optional_lenient
def list_scans():
    """Past scans, newest first."""
    response, status = DiseaseService.list_scans(user_id=current_user_id())
    return jsonify(response), status


@disease_bp.route("/scans/<int:scan_id>", methods=["GET"])
@jwt_optional_lenient
def get_scan(scan_id):
    """Re-open a past scan with the full diagnosis it produced."""
    response, status = DiseaseService.get_scan(scan_id, user_id=current_user_id())
    return jsonify(response), status
