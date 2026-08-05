"""HTTP routes for the targeted spray prescription.

Thin controllers over :class:`app.services.spray_service.SprayService`.

    GET  /api/spray/health                       module + rig capabilities
    POST /api/spray/prescribe                    K-means a capture into zones
    GET  /api/spray/prescriptions                past prescriptions
    GET  /api/spray/prescriptions/<id>           re-open one, with its patches
    POST /api/spray/prescriptions/<id>/plan      what would be flown (no upload)
    POST /api/spray/prescriptions/<id>/execute   send it to the aircraft
    POST /api/spray/stop                         shut the valve, hold position
    GET  /api/spray/output/<path>                prescription map images

The split between *plan* and *execute* is the point: the app shows the plan,
the operator approves it, and only then does anything reach the vehicle.
"""

import os

from flask import Blueprint, current_app, jsonify, request, send_from_directory

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.spray_service import SprayService

spray_bp = Blueprint("spray", __name__)

_OUTPUT_SUBDIR = "spray_outputs"
_CAPTURE_SUBDIR = "captures"


def _output_base() -> str:
    path = os.path.join(current_app.instance_path, _OUTPUT_SUBDIR)
    os.makedirs(path, exist_ok=True)
    return path


def _capture_base() -> str:
    return os.path.join(current_app.instance_path, _CAPTURE_SUBDIR)


@spray_bp.route("/health", methods=["GET"])
def health():
    response, status = SprayService.capabilities()
    return jsonify(response), status


@spray_bp.route("/prescribe", methods=["POST"])
@jwt_optional_lenient
def prescribe():
    """Cluster a multispectral shot into severe / moderate / healthy zones.

    JSON: {"shot_id": "shot_...", "k": 3, "index": "ndvi",
           "dose_l_per_ha": 20, "fov_deg": 62, "field_area_ha": 1.2}
    """
    response, status = SprayService.prescribe(
        payload=request.get_json(silent=True),
        capture_base=_capture_base(),
        output_base=_output_base(),
        url_prefix=request.host_url.rstrip("/") + "/api/spray/output",
        user_id=current_user_id(),
    )
    return jsonify(response), status


@spray_bp.route("/prescriptions", methods=["GET"])
@jwt_optional_lenient
def list_prescriptions():
    response, status = SprayService.list_prescriptions(
        user_id=current_user_id(), session_id=request.args.get("session_id")
    )
    return jsonify(response), status


@spray_bp.route("/prescriptions/<int:prescription_id>", methods=["GET"])
@jwt_optional_lenient
def get_prescription(prescription_id):
    response, status = SprayService.get(prescription_id, user_id=current_user_id())
    return jsonify(response), status


@spray_bp.route("/prescriptions/<int:prescription_id>/plan", methods=["POST"])
@jwt_optional_lenient
def plan(prescription_id):
    """Build the spray mission for a chosen option without uploading it.

    JSON: {"option": "severe_only" | "severe_moderate",
           "altitude_m": 3, "speed_ms": 3}
    """
    response, status = SprayService.plan(
        prescription_id,
        request.get_json(silent=True),
        user_id=current_user_id(),
    )
    return jsonify(response), status


@spray_bp.route("/prescriptions/<int:prescription_id>/execute", methods=["POST"])
@jwt_optional_lenient
def execute(prescription_id):
    """Upload the spray mission; add "start": true to launch it as well."""
    response, status = SprayService.execute(
        prescription_id,
        request.get_json(silent=True),
        user_id=current_user_id(),
    )
    return jsonify(response), status


@spray_bp.route("/stop", methods=["POST"])
@jwt_optional_lenient
def stop():
    """Close the valve now and hold. The in-flight abort."""
    response, status = SprayService.stop(request.get_json(silent=True))
    return jsonify(response), status


@spray_bp.route("/output/<path:relpath>", methods=["GET"])
def output_file(relpath):
    """Serve a rendered prescription map."""
    return send_from_directory(_output_base(), relpath)
