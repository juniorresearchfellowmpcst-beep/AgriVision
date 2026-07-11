"""HTTP routes for drone-mission planning from an uploaded KML file.

Accepts the KML two ways so the frontend can pick whichever is convenient:
  * multipart file upload  -> field name "file"
  * JSON                    -> {"kml": "<kml text>", ...}

Optional params (query string, form field, or JSON): altitude_m, line_spacing_m.
"""

from flask import Blueprint, jsonify, request

from app.services.mission_service import MissionService

mission_bp = Blueprint("mission", __name__)

_ALLOWED_EXT = (".kml",)


def _param(name: str, default):
    """Read a param from JSON body, form data, or query string."""
    data = request.get_json(silent=True) or {}
    if name in data:
        return data[name]
    return request.form.get(name) or request.args.get(name) or default


@mission_bp.route("/upload-kml", methods=["POST"])
def upload_kml():
    """Upload a KML mission file (or JSON) and get back a waypoint mission."""
    altitude = _param("altitude_m", 60.0)
    spacing = _param("line_spacing_m", 20.0)

    kml_text = None

    # 1. multipart file upload
    if "file" in request.files:
        f = request.files["file"]
        if f.filename and not f.filename.lower().endswith(_ALLOWED_EXT):
            return jsonify({"status": "error", "message": "File must be a .kml"}), 400
        try:
            kml_text = f.read().decode("utf-8", errors="replace")
        except Exception:
            return jsonify({"status": "error", "message": "Could not read uploaded file."}), 400

    # 2. raw KML in JSON body
    if kml_text is None:
        data = request.get_json(silent=True) or {}
        kml_text = data.get("kml")

    if not kml_text:
        return jsonify({
            "status": "error",
            "message": "Provide a KML file (multipart field 'file') or {'kml': '...'} JSON.",
        }), 400

    try:
        altitude = float(altitude)
        spacing = float(spacing)
    except (TypeError, ValueError):
        return jsonify({"status": "error", "message": "altitude_m and line_spacing_m must be numbers."}), 400

    response, status = MissionService.plan_from_kml(
        kml_text, altitude_m=altitude, line_spacing_m=spacing
    )
    return jsonify(response), status
