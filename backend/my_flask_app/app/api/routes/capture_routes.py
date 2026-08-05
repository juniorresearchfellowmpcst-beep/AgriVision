"""HTTP routes for live drone camera capture.

Thin controllers over :class:`app.services.capture_service.CaptureService`.

    GET    /api/capture/health           module capabilities
    GET    /api/capture/cameras          registered feeds
    POST   /api/capture/cameras          register a feed
    PATCH  /api/capture/cameras/<id>     edit a feed
    DELETE /api/capture/cameras/<id>     remove a feed
    POST   /api/capture/cameras/test     is this feed live?
    POST   /api/capture/shoot            trigger every enabled camera once
    POST   /api/capture/upload           store frames the app already holds
    GET    /api/capture/sessions         capture sessions, newest first
    GET    /api/capture/frames           frames / shots, filterable
    GET    /api/capture/file/<path>      serve a stored frame or preview
"""

import os

from flask import Blueprint, current_app, jsonify, request, send_from_directory

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.capture_service import CaptureService

capture_bp = Blueprint("capture", __name__)

# Where captured frames live, under the Flask instance folder.
_CAPTURE_SUBDIR = "captures"


def _capture_base() -> str:
    path = os.path.join(current_app.instance_path, _CAPTURE_SUBDIR)
    os.makedirs(path, exist_ok=True)
    return path


def _file_url_prefix() -> str:
    return request.host_url.rstrip("/") + "/api/capture/file"


@capture_bp.route("/health", methods=["GET"])
def health():
    response, status = CaptureService.capabilities()
    return jsonify(response), status


# ── camera registry ──────────────────────────────────────────────────────

@capture_bp.route("/cameras", methods=["GET"])
@jwt_optional_lenient
def list_cameras():
    response, status = CaptureService.list_cameras(user_id=current_user_id())
    return jsonify(response), status


@capture_bp.route("/cameras", methods=["POST"])
@jwt_optional_lenient
def add_camera():
    response, status = CaptureService.add_camera(
        request.get_json(silent=True), user_id=current_user_id()
    )
    return jsonify(response), status


@capture_bp.route("/cameras/<int:camera_id>", methods=["PATCH", "PUT"])
@jwt_optional_lenient
def update_camera(camera_id):
    response, status = CaptureService.update_camera(
        camera_id, request.get_json(silent=True), user_id=current_user_id()
    )
    return jsonify(response), status


@capture_bp.route("/cameras/<int:camera_id>", methods=["DELETE"])
@jwt_optional_lenient
def delete_camera(camera_id):
    response, status = CaptureService.delete_camera(
        camera_id, user_id=current_user_id()
    )
    return jsonify(response), status


@capture_bp.route("/cameras/test", methods=["POST"])
@jwt_optional_lenient
def test_camera():
    """Probe a feed before saving it, so a typo is caught on the bench."""
    data = request.get_json(silent=True) or {}
    response, status = CaptureService.test_camera(
        camera_id=data.get("camera_id"),
        url=data.get("url"),
        user_id=current_user_id(),
    )
    return jsonify(response), status


# ── capture ──────────────────────────────────────────────────────────────

@capture_bp.route("/shoot", methods=["POST"])
@jwt_optional_lenient
def shoot():
    """Grab one frame from every enabled camera, geotagged from telemetry.

    JSON (all optional): {"session_id": "...", "camera_ids": [1,2],
    "field_name": "Block A"}
    """
    data = request.get_json(silent=True) or {}
    response, status = CaptureService.shoot(
        base_dir=_capture_base(),
        session_id=data.get("session_id"),
        camera_ids=data.get("camera_ids"),
        field_name=data.get("field_name"),
        user_id=current_user_id(),
        url_prefix=_file_url_prefix(),
    )
    return jsonify(response), status


@capture_bp.route("/upload", methods=["POST"])
@jwt_optional_lenient
def upload():
    """Store frames posted by the app as a capture shot.

    Multipart: one file part per band, named after the band ('nir', 'red',
    'red_edge', 'green', 'blue') or 'rgb' for the normal camera. Optional
    form fields: session_id, field_name, lat, lon, alt_m, heading_deg.
    """
    files = []
    for field_name, storage in request.files.items(multi=True):
        data = storage.read()
        if data:
            files.append((field_name, storage.filename, data))

    if not files:
        return jsonify({
            "status": "error",
            "message": "Attach at least one image, named after its band "
                       "(nir, red, red_edge, green, blue) or 'rgb'.",
        }), 400

    def _number(name):
        value = request.form.get(name)
        try:
            return float(value) if value not in (None, "") else None
        except (TypeError, ValueError):
            return None

    geotag = {
        "lat": _number("lat"),
        "lon": _number("lon"),
        "alt_m": _number("alt_m"),
        "heading_deg": _number("heading_deg"),
    }
    # An upload with no coordinates falls back to live telemetry (the service
    # handles that); only pass a geotag when the app actually supplied one.
    if geotag["lat"] is None or geotag["lon"] is None:
        geotag = None

    response, status = CaptureService.store_uploaded(
        base_dir=_capture_base(),
        files=files,
        session_id=request.form.get("session_id"),
        field_name=request.form.get("field_name"),
        user_id=current_user_id(),
        url_prefix=_file_url_prefix(),
        geotag=geotag,
    )
    return jsonify(response), status


# ── history ──────────────────────────────────────────────────────────────

@capture_bp.route("/sessions", methods=["GET"])
@jwt_optional_lenient
def list_sessions():
    response, status = CaptureService.list_sessions(user_id=current_user_id())
    return jsonify(response), status


@capture_bp.route("/frames", methods=["GET"])
@jwt_optional_lenient
def list_frames():
    response, status = CaptureService.list_frames(
        user_id=current_user_id(),
        session_id=request.args.get("session_id"),
        shot_id=request.args.get("shot_id"),
        role=request.args.get("role"),
        url_prefix=_file_url_prefix(),
    )
    return jsonify(response), status


@capture_bp.route("/file/<path:relpath>", methods=["GET"])
def serve_file(relpath):
    """Serve a stored frame or its preview."""
    return send_from_directory(_capture_base(), relpath)
