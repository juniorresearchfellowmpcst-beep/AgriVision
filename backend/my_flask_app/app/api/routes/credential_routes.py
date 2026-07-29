"""HTTP routes for pilot credentials (/api/credentials).

Thin controllers over CredentialService, mirroring drone_routes.py. Everything
here is personal paperwork, so every endpoint requires a login — there is no
anonymous view of somebody's licence numbers.

    GET    /api/credentials        list (seeded with blank rows on first read)
    POST   /api/credentials        add one
    PUT    /api/credentials/<id>   edit
    DELETE /api/credentials/<id>   remove
"""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from app.core.jwt import current_user_id
from app.services.credential_service import CredentialService

credential_bp = Blueprint("credentials", __name__)


@credential_bp.route("", methods=["GET"])
@credential_bp.route("/", methods=["GET"])
@jwt_required()
def list_credentials():
    response, status = CredentialService.list_credentials(current_user_id())
    return jsonify(response), status


@credential_bp.route("", methods=["POST"])
@credential_bp.route("/", methods=["POST"])
@jwt_required()
def create_credential():
    response, status = CredentialService.create_credential(
        current_user_id(), request.get_json(silent=True)
    )
    return jsonify(response), status


@credential_bp.route("/<int:credential_id>", methods=["PUT", "PATCH"])
@jwt_required()
def update_credential(credential_id):
    response, status = CredentialService.update_credential(
        current_user_id(), credential_id, request.get_json(silent=True)
    )
    return jsonify(response), status


@credential_bp.route("/<int:credential_id>", methods=["DELETE"])
@jwt_required()
def delete_credential(credential_id):
    response, status = CredentialService.delete_credential(
        current_user_id(), credential_id
    )
    return jsonify(response), status
