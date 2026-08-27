"""Continuous live video off the drone's cameras.

:mod:`app.capture.sources` answers "give me one frame, now". That is the right
shape for a shutter press, and the wrong shape for watching a feed: opening an
RTSP session costs a second or two of handshake and keyframe wait, so a page
that re-opened the camera for every displayed frame would run at a frame every
two seconds and hammer a camera that is also trying to fly.

This module keeps the camera open instead. One reader thread per feed pulls
frames as fast as they arrive into a single-slot buffer, and any number of
consumers -- the MJPEG relay the operator watches, the analyser sampling one
frame every few seconds -- read the latest frame from that slot. The camera
sees exactly one connection no matter how many phones are looking.

Three things this has to survive, because all three happen on a real flight:

  * **The link drops.** A drone flying away from the ground station loses
    frames long before it loses telemetry. The reader reconnects on its own
    with a backoff, and reports ``reconnecting`` rather than pretending the
    last good frame is current.
  * **Nobody is watching.** Streams are reference counted and shut themselves
    down once the last viewer leaves, so a closed app does not keep an RTSP
    session (and the CPU decoding it) alive for the rest of the flight.
  * **A slow consumer.** The buffer is latest-frame-wins, never a queue. A
    phone on bad Wi-Fi falls behind in *time*, not in memory, and the frames
    it does get are the newest ones rather than a growing backlog of stale
    ones.

Nothing here touches Flask or the database -- it is threads and numpy arrays,
so a rig can be exercised from a script.
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np

from .sources import CaptureError, grab_frame, is_snapshot_url, is_stream_url

logger = logging.getLogger(__name__)

# How long a stream stays open with nobody watching before it releases the
# camera. Long enough to survive a page transition or an app backgrounding for
# a moment, short enough that a forgotten tab does not hold the feed all day.
IDLE_SHUTDOWN_S = 20.0

# Reconnect backoff. Starts fast because most drops are a momentary radio
# glitch that clears immediately, and caps low because an operator staring at
# a black rectangle needs it back the instant the link returns.
RECONNECT_MIN_S = 0.5
RECONNECT_MAX_S = 8.0

# A feed that has produced nothing for this long is treated as dead and
# reopened, even though the decoder has not reported an error. RTSP sessions
# fail silently more often than they fail loudly.
STALL_TIMEOUT_S = 10.0

# Poll rate for cameras that only offer a single-shot JPEG endpoint. There is
# no stream to follow, so this is the frame rate -- fast enough to look live,
# slow enough not to melt a small camera's web server.
SNAPSHOT_INTERVAL_S = 0.2

# States a stream reports to the app. Plain strings because they are rendered
# directly in the UI.
STATE_STARTING = "starting"
STATE_LIVE = "live"
STATE_RECONNECTING = "reconnecting"
STATE_STOPPED = "stopped"


class LiveStream:
    """One camera, held open, with its newest frame always available.

    Do not construct these directly -- ask :class:`StreamHub` for one, so the
    reference counting that decides when the camera closes stays correct.
    """

    def __init__(self, key: str, url: str, name: str = ""):
        self.key = key
        self.url = url
        self.name = name or key

        self._lock = threading.Lock()
        # Consumers wait on this rather than polling, so a 30 fps feed is
        # relayed at 30 fps without a sleep loop guessing the interval.
        self._new_frame = threading.Condition(self._lock)

        self._frame: Optional[np.ndarray] = None
        self._seq = 0                      # bumped per frame; consumers track it
        self._frame_at = 0.0               # monotonic stamp of the newest frame

        self._state = STATE_STARTING
        self._last_error: Optional[str] = None
        self._opened_at: Optional[float] = None
        self._frames_read = 0
        self._reconnects = 0
        # Timestamps of recent frames, for an honest measured fps rather than
        # whatever the camera claims in its SDP.
        self._recent: List[float] = []

        self._subscribers = 0
        self._idle_since: Optional[float] = time.monotonic()

        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None

    # -- lifecycle --------------------------------------------------------

    def start(self) -> "LiveStream":
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return self
            self._stop.clear()
            self._state = STATE_STARTING
            self._thread = threading.Thread(
                target=self._run, name=f"livestream-{self.key}", daemon=True
            )
            self._thread.start()
        return self

    def stop(self, wait: bool = False) -> None:
        self._stop.set()
        with self._lock:
            # Release anyone blocked in latest(): the stream is going away and
            # a waiter would otherwise sit until its own timeout.
            self._new_frame.notify_all()
        thread = self._thread
        if wait and thread is not None and thread is not threading.current_thread():
            thread.join(timeout=5.0)

    @property
    def alive(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    # -- subscribers ------------------------------------------------------

    def subscribe(self) -> bool:
        """Join this stream. False when it is already shutting down.

        The refusal matters: a stream that has been idle for its timeout can
        stop in the moment between a caller finding it alive and joining it,
        and a viewer attached to a stopping stream gets a black rectangle that
        never recovers. :meth:`StreamHub.open` answers False by making a fresh
        stream instead.
        """
        with self._lock:
            if self._stop.is_set():
                return False
            self._subscribers += 1
            self._idle_since = None
            return True

    def unsubscribe(self) -> None:
        with self._lock:
            self._subscribers = max(0, self._subscribers - 1)
            if self._subscribers == 0:
                self._idle_since = time.monotonic()

    # -- reading ----------------------------------------------------------

    def latest(
        self, after_seq: int = -1, timeout: float = 5.0
    ) -> Optional[Tuple[np.ndarray, int, float]]:
        """Newest frame strictly newer than ``after_seq``.

        Blocks until one arrives or ``timeout`` elapses. Returns
        ``(frame, seq, monotonic_stamp)``, or ``None`` on timeout or once the
        stream has stopped -- both of which the caller must treat as "no
        picture right now" rather than as an error, because a reconnecting
        feed passes through exactly this state.

        The frame is the live buffer, not a copy: treat it as read-only, and
        copy before writing on it.
        """
        deadline = time.monotonic() + max(0.0, timeout)
        with self._new_frame:
            while True:
                if self._frame is not None and self._seq > after_seq:
                    return self._frame, self._seq, self._frame_at
                if self._stop.is_set():
                    return None
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None
                self._new_frame.wait(remaining)

    def _publish(self, frame: np.ndarray) -> None:
        now = time.monotonic()
        with self._new_frame:
            self._frame = frame
            self._seq += 1
            self._frame_at = now
            self._frames_read += 1
            self._state = STATE_LIVE
            self._last_error = None
            self._recent.append(now)
            if len(self._recent) > 30:
                del self._recent[:-30]
            self._new_frame.notify_all()

    def _fail(self, message: str) -> None:
        with self._new_frame:
            self._state = STATE_RECONNECTING
            self._last_error = message
            # Wake waiters so a viewer sees "reconnecting" promptly instead of
            # sitting out its full timeout against a feed we know is down.
            self._new_frame.notify_all()

    # -- status -----------------------------------------------------------

    def status(self) -> Dict:
        with self._lock:
            age = (time.monotonic() - self._frame_at) if self._frame_at else None
            fps = 0.0
            if len(self._recent) >= 2:
                span = self._recent[-1] - self._recent[0]
                if span > 0:
                    fps = (len(self._recent) - 1) / span
            shape = self._frame.shape if self._frame is not None else None
            return {
                "key": self.key,
                "name": self.name,
                "url": self.url,
                "state": self._state,
                # A frame older than the stall timeout is not a live picture,
                # whatever the decoder thinks.
                "live": self._state == STATE_LIVE
                and age is not None
                and age < STALL_TIMEOUT_S,
                "viewers": self._subscribers,
                "fps": round(fps, 1),
                "frames": self._frames_read,
                "reconnects": self._reconnects,
                "frame_age_s": round(age, 2) if age is not None else None,
                "width": int(shape[1]) if shape else None,
                "height": int(shape[0]) if shape else None,
                "uptime_s": (
                    round(time.monotonic() - self._opened_at, 1)
                    if self._opened_at
                    else None
                ),
                "last_error": self._last_error,
            }

    # -- reader thread ----------------------------------------------------

    def _run(self) -> None:
        backoff = RECONNECT_MIN_S
        try:
            while not self._stop.is_set():
                if self._expire_if_idle():
                    return
                try:
                    ok = self._pump_once()
                except Exception as exc:  # pragma: no cover - driver dependent
                    logger.warning("live feed %s failed: %s", self.key, exc)
                    self._fail(str(exc))
                    ok = False

                if self._stop.is_set():
                    return
                # A clean return means "idle, shutting down", not "retry".
                if ok:
                    return

                self._reconnects += 1
                if self._stop.wait(backoff):
                    return
                backoff = min(RECONNECT_MAX_S, backoff * 2)
        finally:
            with self._new_frame:
                self._state = STATE_STOPPED
                self._new_frame.notify_all()

    def _pump_once(self) -> bool:
        """One connection attempt: True when idle-stopping, False to reconnect."""
        lowered = (self.url or "").strip().lower()
        wants_decoder = is_stream_url(lowered) or (
            lowered.startswith(("http://", "https://")) and not is_snapshot_url(lowered)
        )
        return self._pump_video() if wants_decoder else self._pump_polled()

    def _expire_if_idle(self) -> bool:
        """True when nobody has been watching long enough to close the camera."""
        with self._lock:
            if self._subscribers > 0 or self._idle_since is None:
                return False
            if time.monotonic() - self._idle_since < IDLE_SHUTDOWN_S:
                return False
        logger.info("live feed %s idle -- releasing camera", self.key)
        self._stop.set()
        return True

    def _pump_video(self) -> bool:
        """Hold an RTSP/MJPEG session open, publishing frames as they decode."""
        capture = cv2.VideoCapture(self.url, cv2.CAP_FFMPEG)
        try:
            for prop_name, value in (
                ("CAP_PROP_OPEN_TIMEOUT_MSEC", 8000),
                ("CAP_PROP_READ_TIMEOUT_MSEC", 8000),
                # Depth 1: we want the newest frame, and a deeper queue only
                # buys latency we then have to throw away.
                ("CAP_PROP_BUFFERSIZE", 1),
            ):
                prop = getattr(cv2, prop_name, None)
                if prop is not None:
                    try:
                        capture.set(prop, value)
                    except Exception:
                        pass

            if not capture.isOpened():
                self._fail(
                    f"Could not open {self.url}. Check the camera is powered, "
                    "on this network, and that the stream path is right."
                )
                return False

            self._opened_at = self._opened_at or time.monotonic()
            last_good = time.monotonic()

            while not self._stop.is_set():
                if self._expire_if_idle():
                    return True

                ok, frame = capture.read()
                if not ok or frame is None:
                    # One dropped read is normal on RTSP; a run of them is not.
                    if time.monotonic() - last_good > STALL_TIMEOUT_S:
                        self._fail("The camera stopped sending frames.")
                        return False
                    time.sleep(0.02)
                    continue

                last_good = time.monotonic()
                self._publish(frame)
            return True
        finally:
            capture.release()

    def _pump_polled(self) -> bool:
        """Re-fetch a snapshot endpoint (or re-read a bench file) on a timer."""
        self._opened_at = self._opened_at or time.monotonic()
        consecutive_errors = 0

        while not self._stop.is_set():
            if self._expire_if_idle():
                return True

            started = time.monotonic()
            try:
                frame = grab_frame(self.url, timeout_s=6.0, warmup_frames=1)
                consecutive_errors = 0
                self._publish(frame)
            except CaptureError as exc:
                consecutive_errors += 1
                # Tolerate a couple of misses -- a small camera's web server
                # rejects an overlapping request now and then -- but stop
                # pretending after that.
                if consecutive_errors >= 3:
                    self._fail(str(exc))
                    return False

            elapsed = time.monotonic() - started
            if self._stop.wait(max(0.0, SNAPSHOT_INTERVAL_S - elapsed)):
                return True
        return True


class StreamHub:
    """Every open feed, keyed so two viewers of one camera share one session."""

    def __init__(self):
        self._streams: Dict[str, LiveStream] = {}
        self._lock = threading.Lock()

    def open(self, key: str, url: str, name: str = "") -> LiveStream:
        """Get (starting it if needed) the stream for ``key``.

        The caller owns a subscription from here until it calls
        :meth:`release`, so wrap use in try/finally -- a viewer that leaks its
        subscription keeps the camera open for the rest of the process.
        """
        key = str(key)
        # Two passes at most. The first can lose a race against a stream that
        # idles out in the moment between being found alive and being joined;
        # the second then replaces exactly that stream, and a stream created
        # microseconds ago cannot itself have expired.
        refused: Optional[LiveStream] = None

        for _attempt in (0, 1):
            with self._lock:
                stream = self._streams.get(key)
                # A changed URL means the operator re-pointed the camera; the
                # old session is now watching the wrong thing.
                if stream is not None and stream.url != url:
                    stream.stop()
                    stream = None
                # `stream is refused` is the narrow case: only replace the very
                # stream that turned us away, never one another thread has
                # since put there.
                if stream is None or not stream.alive or stream is refused:
                    stream = LiveStream(key, url, name)
                    self._streams[key] = stream
                    stream.start()

            if stream.subscribe():
                return stream
            refused = stream

        raise CaptureError(f"Could not open a session for camera {key}.")

    def release(self, stream: Optional[LiveStream]) -> None:
        if stream is not None:
            stream.unsubscribe()

    def get(self, key: str) -> Optional[LiveStream]:
        """The stream for ``key`` without subscribing -- for status only."""
        return self._streams.get(str(key))

    def close(self, key: str) -> bool:
        with self._lock:
            stream = self._streams.pop(str(key), None)
        if stream is None:
            return False
        stream.stop()
        return True

    def status(self) -> List[Dict]:
        with self._lock:
            streams = list(self._streams.values())
            # Drop the ones that have finished shutting down, so a status call
            # doubles as the reaper and the dict does not grow across a flight.
            alive: List[Dict] = []
            for stream in streams:
                if stream.alive:
                    alive.append(stream.status())
                else:
                    self._streams.pop(stream.key, None)
        return alive

    def shutdown(self) -> None:
        with self._lock:
            streams = list(self._streams.values())
            self._streams.clear()
        for stream in streams:
            stream.stop()


# One hub per process. Gunicorn with several workers gives each its own -- a
# camera would then see one session per worker, which is why the deployment
# runs a single worker with threads (see gunicorn.conf.py).
hub = StreamHub()


def encode_jpeg(
    frame: np.ndarray, quality: int = 75, max_width: Optional[int] = None
) -> Optional[bytes]:
    """Frame -> JPEG bytes for the relay, or None if it could not be encoded.

    Downscaling happens here rather than on the camera because the operator's
    phone and the analyser want different sizes out of the same feed.
    """
    from .sources import to_preview

    if frame is None or getattr(frame, "size", 0) == 0:
        return None

    # to_preview also rescues a 16-bit band or a single-channel sensor, which
    # would otherwise relay as a black rectangle.
    image = frame
    if image.dtype != np.uint8 or image.ndim != 3 or image.shape[2] != 3:
        image = to_preview(image, max_edge=max_width or 1600)

    if max_width and image.shape[1] > max_width:
        scale = max_width / float(image.shape[1])
        image = cv2.resize(
            image,
            (max_width, max(1, int(image.shape[0] * scale))),
            interpolation=cv2.INTER_AREA,
        )

    ok, buffer = cv2.imencode(
        ".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), int(quality)]
    )
    return buffer.tobytes() if ok else None


# The multipart separator the relay uses. Fixed rather than random because the
# client has to be told it in the Content-Type header anyway, and a constant
# makes a stream readable in curl.
MJPEG_BOUNDARY = "agrivisionframe"

# Sent when the camera has produced nothing for a while. A viewer that gets
# *no* bytes cannot tell a reconnecting feed from a hung server, and most HTTP
# clients will eventually time the request out and tear down a stream that was
# about to recover. A comment part keeps the connection provably alive without
# putting a stale picture on screen.
_KEEPALIVE_EVERY_S = 3.0


def mjpeg_stream(
    stream: "LiveStream",
    fps: float = 12.0,
    quality: int = 75,
    max_width: Optional[int] = None,
):
    """Yield ``multipart/x-mixed-replace`` parts for as long as the client reads.

    The caller owns the subscription (it called :meth:`StreamHub.open`) and
    must release it when this generator finishes -- including when the client
    hangs up, which arrives here as :class:`GeneratorExit`.

    ``fps`` caps how often frames are *sent*, not how fast the camera runs. A
    phone showing a 720p preview does not need 30 fps of a field, and the cap
    is what keeps a handful of viewers from saturating a field radio link.
    """
    interval = 1.0 / max(0.5, float(fps))
    seq = -1
    last_sent = 0.0

    while True:
        # Wait out the rate limit *before* taking a frame, never after. An
        # operator steers by this picture, so the frame that goes on the wire
        # has to be the newest one at the moment of sending — sleeping with a
        # frame already in hand would add the whole interval to its age and
        # discard the fresher frames that arrived during the sleep.
        wait = interval - (time.monotonic() - last_sent)
        if wait > 0:
            time.sleep(wait)

        got = stream.latest(after_seq=seq, timeout=_KEEPALIVE_EVERY_S)
        if got is None:
            if not stream.alive:
                return
            # Feed is reconnecting: prove we are still here and keep waiting.
            yield b"--" + MJPEG_BOUNDARY.encode() + b"\r\n" \
                  b"Content-Type: text/plain\r\n" \
                  b"X-AgriVision-Status: waiting\r\n\r\n\r\n"
            continue

        frame, seq, _stamp = got

        jpeg = encode_jpeg(frame, quality=quality, max_width=max_width)
        if jpeg is None:
            continue
        last_sent = time.monotonic()

        yield (
            b"--" + MJPEG_BOUNDARY.encode() + b"\r\n"
            b"Content-Type: image/jpeg\r\n"
            b"Content-Length: " + str(len(jpeg)).encode() + b"\r\n\r\n"
            + jpeg + b"\r\n"
        )
