"""HTTP routes for drone pairing and live status.

Thin controllers over DroneService, mirroring auth_routes.py. Status/list work
without a login (the app shows the shared demo unit); pairing requires a JWT.
"""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from app.api.schemas.drone_schema import (
    validate_pair_payload,
    validate_telemetry_payload,
)
from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.drone_service import DroneService

drone_bp = Blueprint("drones", __name__)


@drone_bp.route("", methods=["GET"])
@drone_bp.route("/", methods=["GET"])
@jwt_optional_lenient
def list_drones():
    response, status = DroneService.list_drones(user_id=current_user_id())
    return jsonify(response), status


@drone_bp.route("/status", methods=["GET"])
@jwt_optional_lenient
def drone_status():
    response, status = DroneService.get_status(user_id=current_user_id())
    return jsonify(response), status


@drone_bp.route("/pair", methods=["POST"])
@jwt_required()
def pair():
    cleaned, error = validate_pair_payload(request.get_json(silent=True))
    if error:
        return jsonify({"status": "error", "message": error}), 400

    response, status = DroneService.pair(
        user_id=current_user_id(),
        drone_id=cleaned["drone_id"],
        serial_number=cleaned["serial_number"],
    )
    return jsonify(response), status


@drone_bp.route("/unpair", methods=["POST"])
@jwt_required()
def unpair():
    response, status = DroneService.unpair(user_id=current_user_id())
    return jsonify(response), status


@drone_bp.route("/<int:drone_id>/telemetry", methods=["PUT"])
def telemetry(drone_id):
    cleaned, error = validate_telemetry_payload(request.get_json(silent=True))
    if error:
        return jsonify({"status": "error", "message": error}), 400

    response, status = DroneService.update_telemetry(drone_id, cleaned)
    return jsonify(response), status
