"""Gunicorn settings for the AgriVision backend.

Used by the root Procfile:

    gunicorn --chdir backend/my_flask_app -c gunicorn.conf.py run:app

Two decisions here are not the usual ones, and both follow from what this
process holds in memory.

**One worker.** The MAVLink link (``app.mavlink.link``) and the camera stream
hub (``app.capture.live``) are process-local objects with their own threads.
Two workers means two independent links to the same aircraft — both sending
heartbeats, both claiming the same MAVLink system id, and mission uploads
interleaving between them — and two RTSP sessions per camera. The app would
also answer "is the drone connected?" differently depending on which worker
took the request. So: one worker, always.

**Threads, not async.** Every MJPEG viewer occupies a worker thread for the
whole time it watches, and OpenCV's decode releases the GIL, so threads are
what actually gives concurrency here. The count has to cover the watchers plus
the ordinary requests arriving while they watch — hence a thread count well
above ``LIVE_STREAM_MAX_VIEWERS`` (default 8), leaving headroom for the
flight-control endpoints that must stay answerable during a flight.
"""

import multiprocessing
import os


def _int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


bind = f"0.0.0.0:{os.environ.get('PORT', '5000')}"

# See the module docstring. This is not a performance knob — raising it breaks
# the flight link. If this app ever needs several workers, the MAVLink link and
# the stream hub have to move into a separate process first.
workers = 1
worker_class = "gthread"

# Viewers + working headroom. multiprocessing.cpu_count() is not the right
# basis: these threads spend their lives blocked on a socket or inside a
# decode, not competing for CPU.
threads = _int("GUNICORN_THREADS", 24)

# A relayed stream is a response that never ends by design. gthread's worker
# heartbeats come from a separate notify thread, so a long response does not
# look like a hang to the arbiter — but keep the timeout generous anyway, as
# a whole-multispectral-shot capture across five cameras is genuinely slow.
timeout = _int("GUNICORN_TIMEOUT", 300)
graceful_timeout = _int("GUNICORN_GRACEFUL_TIMEOUT", 30)

# Longer than any single request, so a phone polling telemetry every second
# is not paying for a new TCP handshake each time.
keepalive = _int("GUNICORN_KEEPALIVE", 15)

# Unbounded by default; only meaningful behind a proxy that sets it.
forwarded_allow_ips = os.environ.get("FORWARDED_ALLOW_IPS", "127.0.0.1")

accesslog = None          # the app logs its own requests, with request ids
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info").lower()

# Preloading would fork the app *after* import. Harmless today, but it makes
# it far too easy for someone later to start a camera or the MAVLink link at
# import time and end up with threads that do not survive the fork.
preload_app = False

_ = multiprocessing  # documented above; kept so the reasoning is discoverable


def on_starting(server):
    server.log.info(
        "AgriVision API starting: %s worker, %s threads, live viewers capped at %s",
        workers,
        threads,
        os.environ.get("LIVE_STREAM_MAX_VIEWERS", "8"),
    )


def worker_exit(server, worker):
    """Release cameras and the flight link when a worker goes away."""
    try:
        from app.capture.live import hub
        from app.services.live_analysis import manager

        manager.shutdown()
        hub.shutdown()
    except Exception:  # pragma: no cover - best effort during shutdown
        pass
