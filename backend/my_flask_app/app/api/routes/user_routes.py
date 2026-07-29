"""HTTP routes for the signed-in user's profile, settings and sync summary.

    GET/PUT /api/users/me              profile details + flight stats
    GET/PUT /api/users/me/preferences  notification + app toggles
    GET     /api/users/me/sync-status  what the server holds, per record type
"""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from app.core.jwt import current_user_id
from app.services.user_service import UserService

user_bp = Blueprint("users", __name__)


@user_bp.route("/me", methods=["GET"])
@jwt_required()
def get_me():
    response, status = UserService.get_me(current_user_id())
    return jsonify(response), status


@user_bp.route("/me", methods=["PUT"])
@jwt_required()
def update_me():
    response, status = UserService.update_me(
        current_user_id(), request.get_json(silent=True)
    )
    return jsonify(response), status


@user_bp.route("/me/preferences", methods=["GET"])
@jwt_required()
def get_preferences():
    response, status = UserService.get_preferences(current_user_id())
    return jsonify(response), status


@user_bp.route("/me/preferences", methods=["PUT", "PATCH"])
@jwt_required()
def update_preferences():
    """Partial update — send only the toggles that changed."""
    response, status = UserService.update_preferences(
        current_user_id(), request.get_json(silent=True)
    )
    return jsonify(response), status


@user_bp.route("/me/sync-status", methods=["GET"])
@jwt_required()
def sync_status():
    response, status = UserService.sync_status(current_user_id())
    return jsonify(response), status
