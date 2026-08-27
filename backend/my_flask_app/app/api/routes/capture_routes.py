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

Watching the feed live, and analysing it while it runs:

    GET    /api/capture/cameras/<id>/stream    MJPEG relay of the live feed
    GET    /api/capture/cameras/<id>/frame     newest frame as one JPEG
    GET    /api/capture/live                   state of every open feed
    DELETE /api/capture/cameras/<id>/stream    drop the camera session
    POST   /api/capture/cameras/<id>/analyze   start scanning the live feed
    GET    /api/capture/cameras/<id>/analyze   rolling weed/disease readout
    DELETE /api/capture/cameras/<id>/analyze   stop scanning
    GET    /api/capture/cameras/<id>/analyze/frames   recent samples
    GET    /api/capture/analyze                every running analysis
"""

import os

from flask import (
    Blueprint,
    Response,
    current_app,
    jsonify,
    request,
    send_from_directory,
)

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


# ── watching the feed live ───────────────────────────────────────────────
#
# The relay exists so the phone never has to speak RTSP. The cameras are on
# the drone's network and this process is already on it (the MAVLink link
# lives here), so the server decodes once and hands out JPEG frames that any
# HTTP client can render — which also means the analyser below and every
# watching phone share a single session to the camera.
#
# NOTE: each viewer holds one worker thread for as long as it watches. That is
# what gunicorn.conf.py's thread count is sized for, and what MAX_VIEWERS caps.

# Ceiling on concurrent relay clients, so a field full of phones cannot take
# every worker thread and leave the flight-control endpoints unanswerable.
_MAX_VIEWERS_DEFAULT = 8


def _max_viewers() -> int:
    return int(current_app.config.get("LIVE_STREAM_MAX_VIEWERS", _MAX_VIEWERS_DEFAULT))


def _int_arg(name: str, default: int, low: int, high: int) -> int:
    try:
        return max(low, min(high, int(request.args.get(name, default))))
    except (TypeError, ValueError):
        return default


@capture_bp.route("/cameras/<int:camera_id>/stream", methods=["GET"])
@jwt_optional_lenient
def stream_camera(camera_id):
    """Relay the camera as MJPEG for as long as the client keeps reading.

    Query: ``fps`` (1-30), ``quality`` (30-95), ``width`` (160-1920).
    """
    from app.capture.live import MJPEG_BOUNDARY, hub, mjpeg_stream

    camera, error = CaptureService.resolve_camera(camera_id, current_user_id())
    if error:
        return jsonify(error[0]), error[1]
    if not camera.enabled:
        return jsonify({
            "status": "error",
            "message": f"{camera.name} is switched off. Enable it to watch the feed.",
        }), 409

    fps = _int_arg("fps", 12, 1, 30)
    quality = _int_arg("quality", 75, 30, 95)
    width = _int_arg("width", 960, 160, 1920)

    # Everything the generator needs is resolved here, while the request
    # context still exists — the generator outlives it by design.
    stream = hub.open(str(camera.id), camera.url, camera.name)
    if stream.status()["viewers"] > _max_viewers():
        hub.release(stream)
        return jsonify({
            "status": "error",
            "message": "Too many people are watching this feed at once. "
                       "Close one of the other views and try again.",
        }), 503

    def generate():
        try:
            yield from mjpeg_stream(
                stream, fps=fps, quality=quality, max_width=width
            )
        finally:
            # Reached on a clean end *and* on GeneratorExit when the client
            # hangs up. Without it the camera would never be released.
            hub.release(stream)

    response = Response(
        generate(),
        mimetype=f"multipart/x-mixed-replace; boundary={MJPEG_BOUNDARY}",
        direct_passthrough=True,
    )
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    # nginx buffers proxied responses by default, which turns a live relay
    # into a stream that arrives in chunks minutes late.
    response.headers["X-Accel-Buffering"] = "no"
    return response


@capture_bp.route("/cameras/<int:camera_id>/frame", methods=["GET"])
@jwt_optional_lenient
def live_frame(camera_id):
    """The newest frame as a single JPEG.

    For thumbnails and for any client that cannot parse multipart. Reads the
    same held-open session, so it costs a JPEG encode rather than an RTSP
    handshake.
    """
    from app.capture.live import encode_jpeg, hub

    camera, error = CaptureService.resolve_camera(camera_id, current_user_id())
    if error:
        return jsonify(error[0]), error[1]

    width = _int_arg("width", 640, 160, 1920)
    quality = _int_arg("quality", 70, 30, 95)
    wait_s = _int_arg("wait", 6, 1, 20)

    stream = hub.open(str(camera.id), camera.url, camera.name)
    try:
        got = stream.latest(after_seq=-1, timeout=float(wait_s))
        if got is None:
            status = stream.status()
            return jsonify({
                "status": "error",
                "message": status.get("last_error")
                or f"No frame from {camera.name} within {wait_s}s.",
                "stream": status,
            }), 504

        jpeg = encode_jpeg(got[0], quality=quality, max_width=width)
        if jpeg is None:
            return jsonify({
                "status": "error",
                "message": "The frame could not be encoded.",
            }), 500
    finally:
        hub.release(stream)

    response = Response(jpeg, mimetype="image/jpeg")
    response.headers["Cache-Control"] = "no-store"
    return response


@capture_bp.route("/live", methods=["GET"])
@jwt_optional_lenient
def live_status():
    """State of every feed currently held open."""
    from app.capture.live import hub

    return jsonify({"status": "ok", "streams": hub.status()}), 200


@capture_bp.route("/cameras/<int:camera_id>/stream", methods=["DELETE"])
@jwt_optional_lenient
def close_stream(camera_id):
    """Drop the camera session now instead of waiting for it to go idle."""
    from app.capture.live import hub

    _camera, error = CaptureService.resolve_camera(camera_id, current_user_id())
    if error:
        return jsonify(error[0]), error[1]

    closed = hub.close(str(camera_id))
    return jsonify({
        "status": "ok",
        "message": "Feed closed." if closed else "That feed was not open.",
    }), 200


# ── analysing the feed while it runs ─────────────────────────────────────

@capture_bp.route("/cameras/<int:camera_id>/analyze", methods=["POST"])
@jwt_optional_lenient
def start_live_analysis(camera_id):
    """Scan the live feed for weeds and disease while the aircraft flies.

    JSON (all optional): {"crop": "soybean", "interval_s": 3, "window": 40,
    "field_name": "Block A"}
    """
    from app.services.live_analysis import LiveAnalysisService

    camera, error = CaptureService.resolve_camera(camera_id, current_user_id())
    if error:
        return jsonify(error[0]), error[1]

    response, status = LiveAnalysisService.start(request.get_json(silent=True), camera)
    return jsonify(response), status


@capture_bp.route("/cameras/<int:camera_id>/analyze", methods=["GET"])
@jwt_optional_lenient
def live_analysis_status(camera_id):
    """Latest scan plus the rolling field-level answer over the window."""
    from app.services.live_analysis import LiveAnalysisService

    response, status = LiveAnalysisService.status(str(camera_id))
    return jsonify(response), status


@capture_bp.route("/cameras/<int:camera_id>/analyze", methods=["DELETE"])
@jwt_optional_lenient
def stop_live_analysis(camera_id):
    from app.services.live_analysis import LiveAnalysisService

    response, status = LiveAnalysisService.stop(str(camera_id))
    return jsonify(response), status


@capture_bp.route("/cameras/<int:camera_id>/analyze/frames", methods=["GET"])
@jwt_optional_lenient
def live_analysis_frames(camera_id):
    """Recent samples, newest last — the trail behind the current reading."""
    from app.services.live_analysis import LiveAnalysisService

    response, status = LiveAnalysisService.recent(
        str(camera_id), limit=_int_arg("limit", 20, 1, 200)
    )
    return jsonify(response), status


@capture_bp.route("/analyze", methods=["GET"])
@jwt_optional_lenient
def all_live_analyses():
    from app.services.live_analysis import LiveAnalysisService

    response, status = LiveAnalysisService.status()
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
