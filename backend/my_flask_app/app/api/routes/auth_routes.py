"""Sign-up, sign-in and password reset.

Every endpoint here is unauthenticated by definition, which makes them the
only ones an anonymous caller can hammer. They are therefore the only ones
throttled — see :mod:`app.core.ratelimit` for why the limits are shaped the
way they are.
"""

from flask import Blueprint
from flask import request
from flask import jsonify

from app.core.ratelimit import rate_limit
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
@rate_limit("signup", "RATELIMIT_SIGNUP")
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
@rate_limit("signin", "RATELIMIT_SIGNIN")
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
@rate_limit("password_reset", "RATELIMIT_PASSWORD_RESET")
def forgot_password():
    data = request.get_json(silent=True)

    error = _require_fields(data, ["email"])
    if error:
        return jsonify({"message": error}), 400

    response, status = AuthService.forgot_password(data["email"])
    return jsonify(response), status


@auth_bp.route("/reset-password", methods=["POST"])
@rate_limit("password_reset", "RATELIMIT_PASSWORD_RESET")
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
@rate_limit("signin", "RATELIMIT_SIGNIN")
def google_signin():
    data = request.get_json(silent=True)

    error = _require_fields(data, ["id_token"])
    if error:
        return jsonify({"message": error}), 400

    response, status = AuthService.google_signin(data["id_token"])
    return jsonify(response), status

