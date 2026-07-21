"""HTTP routes for the signed-in user's profile (/api/users/me)."""

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
