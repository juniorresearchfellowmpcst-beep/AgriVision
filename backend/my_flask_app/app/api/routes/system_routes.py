"""HTTP routes for connection information and overall system health.

    GET /api/system/links   -> where this backend is reachable, and the exact
                               endpoint to type into Mission Planner / QGC
    GET /api/system/health  -> one call that reports every module's state

Both are open (no login). ``links`` returns private LAN addresses and the ports
this process already listens on, which anyone on the same network can discover
anyway; requiring a token would only mean the operator cannot read the address
they need in order to sign in from a second device.
"""

import os

from flask import Blueprint, jsonify, request

from app.services.system_service import SystemService

system_bp = Blueprint("system", __name__)


def _api_port() -> int:
    """The port the client actually reached us on.

    Taken from the request rather than from configuration, because behind a
    reverse proxy or a port mapping the configured port is not the one the
    operator has to type into another program.
    """
    host = request.host or ""
    if ":" in host:
        try:
            return int(host.rsplit(":", 1)[1])
        except ValueError:
            pass

    # No port in the Host header. On https/http that legitimately means 443/80,
    # but it is also what the test client and some proxies send, so prefer the
    # port this process was told to bind when one was set.
    configured = os.environ.get("PORT")
    if configured:
        try:
            return int(configured)
        except ValueError:
            pass
    return 443 if request.scheme == "https" else 80


@system_bp.route("/links", methods=["GET"])
def links():
    """Addresses for the app, and the inbound endpoint for a ground station."""
    response, status = SystemService.links(
        api_port=_api_port(), api_scheme=request.scheme
    )
    return jsonify(response), status


@system_bp.route("/health", methods=["GET"])
def health():
    """Every module's state in one call.

    The per-feature health endpoints already exist; this aggregates them so a
    deployment check, or the app's settings screen, does not have to make eight
    round trips and stitch the answers together.
    """
    response, status = SystemService.health()
    return jsonify(response), status
