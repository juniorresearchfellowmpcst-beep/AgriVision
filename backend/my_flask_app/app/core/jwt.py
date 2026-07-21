"""Shared JWT helpers for the route layer.

`jwt_required(optional=True)` still rejects the request with a 401 when a
token IS attached but is expired or invalid — which strands a mobile app that
keeps sending a stale token. Read-style endpoints want the lenient behaviour:
a bad token simply means "anonymous".
"""

from functools import wraps

from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request


def jwt_optional_lenient(fn):
    """Like ``jwt_required(optional=True)`` but never fails the request:
    a missing, expired, or invalid token is treated as an anonymous call."""

    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            verify_jwt_in_request(optional=True)
        except Exception:
            pass  # stale/invalid token -> proceed anonymously
        return fn(*args, **kwargs)

    return wrapper


def current_user_id():
    """JWT identity as int, or None when anonymous / token unusable."""
    try:
        identity = get_jwt_identity()
        return int(identity) if identity is not None else None
    except Exception:
        return None
