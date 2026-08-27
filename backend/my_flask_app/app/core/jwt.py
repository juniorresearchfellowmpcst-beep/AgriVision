"""Shared JWT helpers for the route layer.

`jwt_required(optional=True)` still rejects the request with a 401 when a
token IS attached but is expired or invalid — which strands a mobile app that
keeps sending a stale token. Read-style endpoints want the lenient behaviour:
a bad token simply means "anonymous".

That leniency is a deliberate product choice, not an oversight. AgriVision's
normal deployment is a ground station on a closed field network: the operator
registers cameras and flies before anyone has signed in, and anonymous rows
(``user_id`` NULL) belong to everyone on that box. An endpoint that refused to
answer without a token would make the app unusable in exactly the situation it
was built for.

It is the wrong default for a backend reachable from the internet, though, so
``REQUIRE_AUTH=1`` flips every endpoint using these helpers to strict. It is
off by default because turning it on changes what the product *is* — see
docs/DEPLOYMENT.md.
"""

from functools import wraps

from flask import current_app, jsonify
from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request


def jwt_optional_lenient(fn):
    """Treat a missing, expired, or invalid token as an anonymous call.

    Unless ``REQUIRE_AUTH`` is set, in which case the request is refused with
    a 401 the app can act on.
    """

    @wraps(fn)
    def wrapper(*args, **kwargs):
        strict = bool(current_app.config.get("REQUIRE_AUTH"))

        try:
            verify_jwt_in_request(optional=not strict)
        except Exception:
            if strict:
                # Same shape as every other error the app parses, and worded
                # for the person reading it rather than quoting the JWT
                # library's internals.
                return jsonify({
                    "status": "error",
                    "message": "Sign in to use this. Your session may have "
                               "expired — sign in again.",
                }), 401
            pass  # stale/invalid token -> proceed anonymously

        if strict and get_jwt_identity() is None:
            return jsonify({
                "status": "error",
                "message": "Sign in to use this.",
            }), 401

        return fn(*args, **kwargs)

    return wrapper


def current_user_id():
    """JWT identity as int, or None when anonymous / token unusable."""
    try:
        identity = get_jwt_identity()
        return int(identity) if identity is not None else None
    except Exception:
        return None
