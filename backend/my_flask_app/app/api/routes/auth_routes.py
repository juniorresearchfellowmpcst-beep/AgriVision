from flask import Blueprint
from flask import request
from flask import jsonify

from app.services.auth_service import AuthService

auth_bp = Blueprint("auth", __name__)


def _require_fields(data, fields):
    if not isinstance(data, dict):
        return "Request body must be JSON"
    missing = [field for field in fields if not data.get(field)]
    if missing:
        return f"Missing required field(s): {', '.join(missing)}"
    return None


@auth_bp.route("/signup", methods=["POST"])
def signup():
    data = request.get_json(silent=True)

    error = _require_fields(data, ["name", "email", "password"])
    if error:
        return jsonify({"message": error}), 400

    response, status = AuthService.signup(
        data["name"],
        data["email"],
        data["password"],
    )

    return jsonify(response), status


@auth_bp.route("/signin", methods=["POST"])
def signin():
    data = request.get_json(silent=True)

    error = _require_fields(data, ["email", "password"])
    if error:
        return jsonify({"message": error}), 400

    response, status = AuthService.signin(
        data["email"],
        data["password"],
    )

    return jsonify(response), status


@auth_bp.route("/forgot-password", methods=["POST"])
def forgot_password():
    data = request.get_json(silent=True)

    error = _require_fields(data, ["email"])
    if error:
        return jsonify({"message": error}), 400

    response, status = AuthService.forgot_password(data["email"])
    return jsonify(response), status


@auth_bp.route("/reset-password", methods=["POST"])
def reset_password():
    data = request.get_json(silent=True)

    error = _require_fields(data, ["email", "otp", "password"])
    if error:
        return jsonify({"message": error}), 400

    response, status = AuthService.reset_password(
        data["email"],
        data["otp"],
        data["password"],
    )
    return jsonify(response), status


@auth_bp.route("/google", methods=["POST"])
def google_signin():
    data = request.get_json(silent=True)

    error = _require_fields(data, ["id_token"])
    if error:
        return jsonify({"message": error}), 400

    response, status = AuthService.google_signin(data["id_token"])
    return jsonify(response), status

