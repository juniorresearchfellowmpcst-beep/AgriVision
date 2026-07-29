"""HTTP routes for the MAVLink link (/api/mavlink).

Thin controllers over MavlinkService, mirroring drone_routes.py. The mobile
app uses them in this order:

    POST /api/mavlink/connect     {"url": "udpin:0.0.0.0:14550"}   open the link
    GET  /api/mavlink/status                                       poll telemetry
    POST /api/mavlink/mission     {"mission_id": 7} | {"waypoints": [...]}
    POST /api/mavlink/start                                        fly it
    POST /api/mavlink/command     {"action": "rtl"}                in-flight actions
    POST /api/mavlink/disconnect

Status is JWT-optional so the live map keeps updating even when a stored token
has gone stale; anything that moves the aircraft requires a valid login.
"""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.mavlink_service import MavlinkService

mavlink_bp = Blueprint("mavlink", __name__)


@mavlink_bp.route("/status", methods=["GET"])
@jwt_optional_lenient
def status():
    """Link state + latest telemetry snapshot (safe to poll at 1-2 Hz)."""
    response, code = MavlinkService.status()
    return jsonify(response), code


@mavlink_bp.route("/connect", methods=["POST"])
@jwt_required()
def connect():
    response, code = MavlinkService.connect(request.get_json(silent=True))
    return jsonify(response), code


@mavlink_bp.route("/disconnect", methods=["POST"])
@jwt_required()
def disconnect():
    response, code = MavlinkService.disconnect()
    return jsonify(response), code


@mavlink_bp.route("/mission", methods=["POST"])
@jwt_optional_lenient
def upload_mission():
    """Write a planned mission to the vehicle (or validate it with dry_run)."""
    response, code = MavlinkService.upload_mission(
        request.get_json(silent=True), user_id=current_user_id()
    )
    return jsonify(response), code


@mavlink_bp.route("/start", methods=["POST"])
@jwt_required()
def start_mission():
    response, code = MavlinkService.start_mission(request.get_json(silent=True))
    return jsonify(response), code


@mavlink_bp.route("/command", methods=["POST"])
@jwt_required()
def command():
    """arm | disarm | takeoff | rtl | land | hold | auto | guided."""
    response, code = MavlinkService.command(request.get_json(silent=True))
    return jsonify(response), code
