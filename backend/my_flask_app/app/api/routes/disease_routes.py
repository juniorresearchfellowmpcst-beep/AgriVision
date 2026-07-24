"""HTTP routes for plant-leaf disease identification.

Thin controllers over :class:`app.services.disease_service.DiseaseService`,
mirroring the other route modules. The endpoints are open (no login required)
so the app can offer disease scanning to anonymous users, exactly like the
multispectral analyzer.

    GET  /api/disease/health     -> module capabilities
    POST /api/disease/identify   -> multipart photo in -> diagnosis + solution
"""

from flask import Blueprint, jsonify, request

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
def identify():
    """Identify the disease in an uploaded leaf photo and return a solution.

    Multipart form-data with a single image file part (any field name). Returns
    the condition name, severity, symptoms, causes, treatment solutions and
    prevention tips.
    """
    image_bytes, filename = _first_upload()
    if image_bytes is None:
        return jsonify({
            "status": "error",
            "message": "Attach a photo of the plant leaf (multipart file part).",
        }), 400

    response, status = DiseaseService.identify(image_bytes, filename=filename)
    return jsonify(response), status
