"""A throttle for the endpoints where guessing pays.

Sign-in, sign-up and password reset are the three places where an unlimited
number of tries is worth something to somebody: a password can be guessed, an
account can be enumerated by watching which emails are accepted, and a reset
endpoint that will send unlimited mail is a way to use this server to harass
someone else's inbox.

This is a fixed-window counter held in process memory, not Flask-Limiter. The
reason is the deployment: AgriVision runs as **one** gunicorn worker with
threads (the MAVLink link and the camera relay both live in process memory and
cannot be shared between workers), so a per-process counter *is* the whole
server. Reaching for a limiter library would add a dependency and a Redis
story to solve a multi-process problem this app does not have. If it ever
grows to several workers, the MAVLink link has to move out first, and this
should become Flask-Limiter with a shared backend at the same time.

What it deliberately does not do is lock accounts. Locking on failed attempts
turns a throttle into a denial-of-service against the operator, who may be in
a field and unable to do anything about it.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from functools import wraps
from typing import Callable, Deque, Dict, Tuple

from flask import current_app, jsonify, request


class _Window:
    """Timestamps of recent attempts, keyed by caller."""

    def __init__(self):
        self._hits: Dict[str, Deque[float]] = {}
        self._lock = threading.Lock()
        self._last_sweep = time.monotonic()

    def hit(self, key: str, limit: int, window_s: float) -> Tuple[bool, float]:
        """Record an attempt. Returns ``(allowed, retry_after_seconds)``."""
        now = time.monotonic()
        cutoff = now - window_s

        with self._lock:
            self._sweep(now, window_s)
            hits = self._hits.setdefault(key, deque())
            while hits and hits[0] < cutoff:
                hits.popleft()

            if len(hits) >= limit:
                # Time until the oldest attempt in the window ages out.
                return False, max(1.0, hits[0] + window_s - now)

            hits.append(now)
            return True, 0.0

    def _sweep(self, now: float, window_s: float) -> None:
        """Drop keys nobody has used in a while.

        Without this the dict grows one entry per distinct client address for
        the life of the process — small, but unbounded, and this process is
        meant to run for days.
        """
        if now - self._last_sweep < window_s:
            return
        self._last_sweep = now
        cutoff = now - window_s
        for key in [k for k, hits in self._hits.items() if not hits or hits[-1] < cutoff]:
            self._hits.pop(key, None)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


_windows: Dict[str, _Window] = {}
_windows_lock = threading.Lock()


def _window_for(name: str) -> _Window:
    with _windows_lock:
        return _windows.setdefault(name, _Window())


def _caller_key() -> str:
    """Who is asking.

    ``remote_addr`` is only trustworthy when PROXY_COUNT is set to match the
    number of proxies in front of the app — otherwise a client can put
    whatever it likes in X-Forwarded-For and get a fresh quota per request.
    ProxyFix in the app factory is what makes this honest; see Config.
    """
    return request.remote_addr or "unknown"


def rate_limit(name: str, limit_key: str) -> Callable:
    """Throttle a view by caller address.

    ``limit_key`` names the ``RATELIMIT_*`` config entry holding the allowance,
    so the numbers stay in one place and stay tunable per deployment.
    """

    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            if not current_app.config.get("RATELIMIT_ENABLED", True):
                return fn(*args, **kwargs)

            limit = int(current_app.config.get(limit_key, 10))
            window_s = float(current_app.config.get("RATELIMIT_WINDOW_S", 300))

            allowed, retry_after = _window_for(name).hit(
                f"{name}:{_caller_key()}", limit, window_s
            )
            if allowed:
                return fn(*args, **kwargs)

            wait = int(retry_after)
            response = jsonify({
                "status": "error",
                # Says what to do, and does not confirm whether the credential
                # was right — that would make the throttle an oracle.
                "message": (
                    f"Too many attempts. Try again in {max(1, wait // 60)} "
                    f"minute(s)." if wait >= 60 else
                    f"Too many attempts. Try again in {max(1, wait)} seconds."
                ),
            })
            response.status_code = 429
            response.headers["Retry-After"] = str(max(1, wait))
            return response

        return wrapper

    return decorator


def reset_all() -> None:
    """Clear every window — for tests, and for an operator locked out on the
    bench who has console access to the process."""
    with _windows_lock:
        for window in _windows.values():
            window.reset()
