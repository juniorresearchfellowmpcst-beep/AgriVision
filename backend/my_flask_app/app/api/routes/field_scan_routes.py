"""HTTP routes for the weed + disease field scan.

Thin controllers over :class:`app.services.field_scan_service.FieldScanService`.

    GET  /api/fieldscan/health          engines in use + crop list
    GET  /api/fieldscan/catalog         crops, their diseases, and their weeds
    POST /api/fieldscan/analyze         one canopy frame -> weeds + disease
    POST /api/fieldscan/session         scan a whole low-pace pass
    GET  /api/fieldscan/scans           past scans, newest first
    GET  /api/fieldscan/scans/<id>      one scan with its full detail
    GET  /api/fieldscan/summary         field-level answer for a session
    GET  /api/fieldscan/output/<path>   weed overlay images

Open (no login required), like the disease and analysis endpoints.
"""

import os

from flask import Blueprint, current_app, jsonify, request, send_from_directory

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.field_scan_service import FieldScanService

field_scan_bp = Blueprint("field_scan", __name__)

_OUTPUT_SUBDIR = "fieldscan_outputs"
_CAPTURE_SUBDIR = "captures"


def _output_base() -> str:
    path = os.path.join(current_app.instance_path, _OUTPUT_SUBDIR)
    os.makedirs(path, exist_ok=True)
    return path


def _capture_base() -> str:
    return os.path.join(current_app.instance_path, _CAPTURE_SUBDIR)


def _url_prefix() -> str:
    return request.host_url.rstrip("/") + "/api/fieldscan/output"


def _first_upload():
    """(bytes, filename) for the first non-empty file part, any field name."""
    for _field_name, storage in request.files.items(multi=True):
        data = storage.read()
        if data:
            return data, storage.filename
    return None, None


@field_scan_bp.route("/health", methods=["GET"])
def health():
    response, status = FieldScanService.capabilities()
    return jsonify(response), status


@field_scan_bp.route("/catalog", methods=["GET"])
def catalog():
    """Crops and diseases (optionally for one crop), plus its usual weeds."""
    response, status = FieldScanService.catalog(crop=request.args.get("crop"))
    return jsonify(response), status


@field_scan_bp.route("/analyze", methods=["POST"])
@jwt_optional_lenient
def analyze():
    """Scan one canopy frame for weeds and disease.

    Multipart: one image part (any field name), plus optional form fields
    ``crop``, ``field_name``, ``lat``, ``lon``, ``target``
    (``disease`` | ``weed`` | ``both``).
    """
    image_bytes, filename = _first_upload()
    if image_bytes is None:
        return jsonify({
            "status": "error",
            "message": "Attach a frame of the crop canopy (multipart file part).",
        }), 400

    def _number(name):
        value = request.form.get(name)
        try:
            return float(value) if value not in (None, "") else None
        except (TypeError, ValueError):
            return None

    response, status = FieldScanService.analyze(
        image_bytes,
        crop=request.form.get("crop"),
        output_base=_output_base(),
        url_prefix=_url_prefix(),
        filename=filename,
        user_id=current_user_id(),
        field_name=request.form.get("field_name") or None,
        lat=_number("lat"),
        lon=_number("lon"),
        target=request.form.get("target") or "both",
    )
    return jsonify(response), status


@field_scan_bp.route("/session", methods=["POST"])
@jwt_optional_lenient
def scan_session():
    """Scan every RGB frame in a capture session and summarise the field.

    JSON: {"session_id": "sess_...", "crop": "soybean", "limit": 40}
    """
    response, status = FieldScanService.scan_session(
        payload=request.get_json(silent=True),
        capture_base=_capture_base(),
        output_base=_output_base(),
        url_prefix=_url_prefix(),
        user_id=current_user_id(),
    )
    return jsonify(response), status


@field_scan_bp.route("/scans", methods=["GET"])
@jwt_optional_lenient
def list_scans():
    response, status = FieldScanService.list_scans(
        user_id=current_user_id(),
        session_id=request.args.get("session_id"),
        crop=request.args.get("crop"),
        url_prefix=_url_prefix(),
    )
    return jsonify(response), status


@field_scan_bp.route("/scans/<int:scan_id>", methods=["GET"])
@jwt_optional_lenient
def get_scan(scan_id):
    response, status = FieldScanService.get_scan(
        scan_id, user_id=current_user_id(), url_prefix=_url_prefix()
    )
    return jsonify(response), status


@field_scan_bp.route("/summary", methods=["GET"])
@jwt_optional_lenient
def summary():
    """Field-level answer for a session, from the scans already recorded."""
    response, status = FieldScanService.summary(
        session_id=request.args.get("session_id", ""), user_id=current_user_id()
    )
    return jsonify(response), status


@field_scan_bp.route("/output/<path:relpath>", methods=["GET"])
def output_file(relpath):
    """Serve a weed overlay image."""
    return send_from_directory(_output_base(), relpath)
