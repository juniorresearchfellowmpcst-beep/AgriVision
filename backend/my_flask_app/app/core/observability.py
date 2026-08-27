"""Logging, request tracing, and turning failures into answers.

Three things a deployment needs that a development server does not:

  * **Logs with a shape.** ``print`` is fine at a desk. A ground station that
    has been running through a morning of flights needs to be able to answer
    "what happened at 10:42" — which means a level, a timestamp, and the
    request the line belongs to.
  * **A request id.** One capture triggers a relay, a scan and a MAVLink call.
    When one of them fails, the id is what ties the operator's screenshot to
    the four log lines that explain it. It is echoed back in a header so a
    support conversation can start from "what does it say under the error".
  * **Errors that are still JSON.** An unhandled exception in Flask returns an
    HTML page. The app's Dio client then fails to parse it and shows "Network
    error — please try again" — which is not what happened, tells the operator
    nothing, and hides the one message that would have helped. Every failure
    leaves here as ``{"status": "error", "message": ...}``.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
import uuid
from typing import Any, Dict

from flask import Flask, g, jsonify, request
from werkzeug.exceptions import HTTPException

# Header carrying the id, in and out. Accepting an inbound one means a request
# id chosen by a client (or by an upstream proxy) survives into our logs.
REQUEST_ID_HEADER = "X-Request-ID"

_LOGGER_NAME = "agrivision"


class _RequestIdFilter(logging.Filter):
    """Attaches the current request's id to every record, if there is one."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = getattr(g, "request_id", "-") if _in_request() else "-"
        return True


def _in_request() -> bool:
    try:
        return bool(request)
    except Exception:
        return False


class _JsonFormatter(logging.Formatter):
    """One JSON object per line, for a log aggregator."""

    def format(self, record: logging.LogRecord) -> str:
        payload: Dict[str, Any] = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", "-"),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        # Anything a caller attached with logger.info(..., extra={...}).
        for key, value in getattr(record, "__dict__", {}).items():
            if key.startswith("agri_"):
                payload[key[5:]] = value
        return json.dumps(payload, default=str)


def configure_logging(app: Flask) -> None:
    """Send everything through one handler at the configured level."""
    level = getattr(logging, str(app.config.get("LOG_LEVEL", "INFO")), logging.INFO)

    # A Windows console defaults to cp1252, and one non-ASCII character in a
    # camera name or an error message then raises UnicodeEncodeError *inside
    # the log handler* — which is how a ground station ends up printing a
    # logging traceback instead of the line that mattered.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):  # not a real stream (captured, piped)
        pass

    handler = logging.StreamHandler(sys.stdout)
    handler.addFilter(_RequestIdFilter())
    if app.config.get("LOG_JSON"):
        handler.setFormatter(_JsonFormatter())
    else:
        handler.setFormatter(
            logging.Formatter(
                "%(asctime)s %(levelname)-7s [%(request_id)s] %(name)s: %(message)s",
                datefmt="%H:%M:%S",
            )
        )

    root = logging.getLogger()
    # Replace rather than add: gunicorn and Flask both install handlers, and
    # three handlers means every line printed three times.
    for existing in list(root.handlers):
        root.removeHandler(existing)
    root.addHandler(handler)
    root.setLevel(level)

    app.logger.handlers = []
    app.logger.propagate = True
    app.logger.setLevel(level)

    # These two are chatty at INFO and say nothing we do not already log.
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    logging.getLogger("matplotlib").setLevel(logging.WARNING)


def register_request_tracing(app: Flask) -> None:
    """Give every request an id, and log how it went."""
    logger = logging.getLogger(_LOGGER_NAME)

    @app.before_request
    def _start_request():
        g.request_id = request.headers.get(REQUEST_ID_HEADER) or uuid.uuid4().hex[:12]
        g.request_started = time.monotonic()

    @app.after_request
    def _finish_request(response):
        response.headers[REQUEST_ID_HEADER] = getattr(g, "request_id", "-")

        started = getattr(g, "request_started", None)
        if started is None:
            return response

        duration_ms = int((time.monotonic() - started) * 1000)
        # An MJPEG relay is open for as long as someone watches; logging its
        # "duration" on completion would report minutes and imply a problem.
        streaming = response.direct_passthrough
        level = logging.WARNING if response.status_code >= 500 else logging.INFO
        logger.log(
            level,
            "%s %s -> %s%s",
            request.method,
            request.full_path.rstrip("?"),
            response.status_code,
            " (streaming)" if streaming else f" in {duration_ms}ms",
        )
        return response


def register_error_handlers(app: Flask) -> None:
    """Every failure answers JSON, in the shape the app already parses."""
    logger = logging.getLogger(_LOGGER_NAME)

    def _payload(message: str, **extra) -> Dict[str, Any]:
        body = {"status": "error", "message": message}
        request_id = getattr(g, "request_id", None)
        if request_id:
            body["request_id"] = request_id
        body.update(extra)
        return body

    @app.errorhandler(HTTPException)
    def _http_error(error: HTTPException):
        # Routes that already answer with jsonify never reach here; this is
        # for the ones Flask raises itself — 404 on an unknown path, 405 on
        # the wrong verb, 413 on an oversized body.
        message = error.description or error.name
        if error.code == 404:
            message = f"No such endpoint: {request.method} {request.path}"
        elif error.code == 405:
            message = (
                f"{request.method} is not allowed on {request.path}."
            )
        elif error.code == 413:
            limit_mb = app.config.get("MAX_CONTENT_LENGTH", 0) // (1024 * 1024)
            message = (
                f"That upload is too large. The limit is {limit_mb} MB — send "
                "a smaller frame, or capture at a lower resolution."
            )
        return jsonify(_payload(message, code=error.code)), error.code

    @app.errorhandler(Exception)
    def _unhandled(error: Exception):
        logger.exception("unhandled error on %s %s", request.method, request.path)

        # The exception text can carry a database URL or a camera password.
        # It goes to the log, which is ours; the client gets the request id to
        # quote instead.
        if app.config.get("DEBUG") or app.config.get("TESTING"):
            detail = f"{type(error).__name__}: {error}"
        else:
            detail = (
                "Something went wrong on the server. Quote this request id if "
                "you report it."
            )
        return jsonify(_payload(detail, code=500)), 500


def register_health(app: Flask) -> None:
    """Two endpoints for whatever is watching the process.

    Deliberately separate from ``/api/system/health``, which reports what
    every *module* thinks of itself and is for the operator. These are for a
    load balancer or a systemd unit, and the distinction matters: liveness
    must not fail because a camera is unplugged, or the supervisor will
    restart a perfectly healthy server in the middle of a flight.
    """

    @app.route("/healthz", methods=["GET"])
    def _healthz():
        """Is the process up? Nothing else — no database, no hardware."""
        return jsonify({"status": "ok", "service": "agrivision-api"}), 200

    @app.route("/readyz", methods=["GET"])
    def _readyz():
        """Can it actually serve? Checks the one dependency it cannot fake."""
        from sqlalchemy import text

        from app.core.database import db

        try:
            db.session.execute(text("SELECT 1"))
            db.session.commit()
        except Exception as exc:
            logging.getLogger(_LOGGER_NAME).error("readiness check failed: %s", exc)
            db.session.rollback()
            return jsonify({
                "status": "error",
                "ready": False,
                "message": "The database is not reachable.",
            }), 503

        return jsonify({
            "status": "ok",
            "ready": True,
            "env": app.config.get("APP_ENV"),
            "version": os.environ.get("APP_VERSION", "dev"),
        }), 200
