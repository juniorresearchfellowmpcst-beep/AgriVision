"""Grabbing still frames from the drone's live camera feeds.

Two kinds of camera hang off an AgriVision aircraft, and this module hides the
difference between them behind one call, :func:`grab_frame`:

  * a **multispectral rig** — one narrow-band sensor per band (blue, green,
    red, red-edge, NIR), each exposing its own stream. One "shot" pulls every
    band at as close to the same instant as the network allows, because the
    K-means prescription downstream compares the bands pixel for pixel.
  * a **normal IP camera** — ordinary RGB video the operator watches, and the
    frame source for the weed / disease CNN.

Supported URL forms (whatever the camera happens to speak)::

    rtsp://user:pass@192.168.1.50:554/stream1    RTSP — most IP cameras
    http://192.168.1.50/mjpg/video.mjpg          MJPEG stream
    http://192.168.1.50/snapshot.jpg             single-shot JPEG endpoint
    F:/captures/bench/nir.tif                    a local file (bench testing)

Nothing here touches the database or Flask: it is pure "bytes off the wire ->
numpy array", so a rig can be exercised from a script or a test.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np

logger = logging.getLogger(__name__)

# FFmpeg's own give-up timers, in microseconds. Without these a camera that
# has dropped off the network holds the request thread for FFmpeg's default —
# about half a minute — and OpenCV's CAP_PROP_OPEN_TIMEOUT_MSEC is honoured by
# some builds and quietly ignored by others, so it cannot be relied on alone.
# ('stimeout' is the older FFmpeg spelling, 'timeout' the current one; setting
# both covers whichever build is installed.) An operator who has already set
# this is left alone.
os.environ.setdefault(
    "OPENCV_FFMPEG_CAPTURE_OPTIONS",
    "rtsp_transport;tcp|stimeout;8000000|timeout;8000000",
)

# Extensions that mean "this URL already is a single image".
_IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff")

# Path fragments used by the common snapshot endpoints (Hikvision, Dahua,
# Amcrest, ESP32-CAM, MJPG-streamer…), so we fetch them with plain HTTP
# instead of asking FFmpeg to open a "video" that is one JPEG long.
_SNAPSHOT_HINTS = ("snapshot", "snap.", "shot.jpg", "jpg/image", "capture", "still")

# Frames pulled off an RTSP/MJPEG stream before the one we keep. A freshly
# opened capture hands back whatever was already sitting in the decoder's
# buffer, which on a 1-2 s GOP can be *seconds* stale — old enough that the
# geotag we stamp on it belongs to a different part of the field.
DEFAULT_WARMUP_FRAMES = 4


class CaptureError(RuntimeError):
    """A feed could not be read — always with a message worth showing."""


def is_stream_url(url: str) -> bool:
    """True when the URL needs a video decoder rather than a plain GET."""
    lowered = (url or "").strip().lower()
    return lowered.startswith(("rtsp://", "rtmp://", "udp://", "tcp://"))


def is_snapshot_url(url: str) -> bool:
    """True when a single HTTP GET returns one complete image."""
    lowered = (url or "").strip().lower()
    if not lowered.startswith(("http://", "https://")):
        return False
    path = lowered.split("?", 1)[0]
    if path.endswith(_IMAGE_EXTS):
        return True
    return any(hint in lowered for hint in _SNAPSHOT_HINTS)


def _decode(buffer: bytes, source: str) -> np.ndarray:
    """Decode image bytes, keeping 16-bit depth for multispectral bands."""
    if not buffer:
        raise CaptureError(f"{source} returned no data.")
    array = np.frombuffer(buffer, dtype=np.uint8)
    # ANYDEPTH|UNCHANGED preserves the 12/16-bit DN a multispectral sensor
    # sends; IMREAD_COLOR would silently crush it to 8 bits and flatten the
    # NIR-vs-Red separation every vegetation index depends on.
    image = cv2.imdecode(array, cv2.IMREAD_ANYDEPTH | cv2.IMREAD_UNCHANGED)
    if image is None:
        raise CaptureError(f"{source} did not return a decodable image.")
    return image


def _grab_snapshot(url: str, timeout_s: float) -> np.ndarray:
    import requests  # local import: only the HTTP path needs it

    try:
        response = requests.get(url, timeout=timeout_s, stream=False)
    except Exception as exc:
        raise CaptureError(f"Could not reach {url}: {exc}") from exc

    if response.status_code != 200:
        raise CaptureError(
            f"{url} answered HTTP {response.status_code}. Check the snapshot "
            "path and any camera username/password in the URL."
        )
    return _decode(response.content, url)


def _grab_local(path: str) -> np.ndarray:
    if not os.path.isfile(path):
        raise CaptureError(f"No such image file: {path}")
    image = cv2.imread(path, cv2.IMREAD_ANYDEPTH | cv2.IMREAD_UNCHANGED)
    if image is None:
        raise CaptureError(f"Could not decode image file: {path}")
    return image


def _grab_stream(url: str, timeout_s: float, warmup_frames: int) -> np.ndarray:
    capture = cv2.VideoCapture(url, cv2.CAP_FFMPEG)

    # FFmpeg honours these; other backends ignore them. Without an open
    # timeout a camera that has gone off the network hangs the request thread
    # for the whole of FFmpeg's own (very long) default.
    for prop_name, value in (
        ("CAP_PROP_OPEN_TIMEOUT_MSEC", int(timeout_s * 1000)),
        ("CAP_PROP_READ_TIMEOUT_MSEC", int(timeout_s * 1000)),
        ("CAP_PROP_BUFFERSIZE", 1),
    ):
        prop = getattr(cv2, prop_name, None)
        if prop is not None:
            try:
                capture.set(prop, value)
            except Exception:
                pass

    try:
        if not capture.isOpened():
            raise CaptureError(
                f"Could not open the video feed at {url}. Check the camera is "
                "powered, on this network, and that the stream path is right."
            )

        frame = None
        deadline = time.time() + timeout_s
        # Read past the buffered backlog; keep the freshest frame we managed
        # to decode so a slow link still yields *something* rather than
        # failing outright.
        for _ in range(max(1, warmup_frames)):
            if time.time() > deadline:
                break
            ok, candidate = capture.read()
            if ok and candidate is not None:
                frame = candidate

        if frame is None:
            raise CaptureError(
                f"Opened {url} but no frame arrived within {timeout_s:.0f}s."
            )
        return frame
    finally:
        capture.release()


def _with_deadline(work, timeout_s: float, url: str) -> np.ndarray:
    """Run a blocking grab on a worker thread and give up on time.

    The belt to FFmpeg's braces. Even with the capture options set above, a
    decoder can sit inside a single blocking call for longer than we promised
    the caller — and the caller here is an HTTP request an operator is staring
    at. The worker is left to unwind on its own; what matters is that the
    request returns something readable instead of hanging.
    """
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout

    pool = ThreadPoolExecutor(max_workers=1)
    try:
        future = pool.submit(work)
        try:
            return future.result(timeout=timeout_s + 2.0)
        except FutureTimeout:
            raise CaptureError(
                f"{url} did not respond within {timeout_s:.0f}s. Check the "
                "camera is powered and reachable from the server."
            )
    finally:
        # Don't block on a worker that is still stuck in the decoder.
        pool.shutdown(wait=False)


def grab_frame(
    url: str,
    timeout_s: float = 8.0,
    warmup_frames: int = DEFAULT_WARMUP_FRAMES,
) -> np.ndarray:
    """Pull one still frame from a camera feed.

    Args:
        url: RTSP/MJPEG stream, HTTP snapshot endpoint, or a local file path.
        timeout_s: give-up budget for opening and reading.
        warmup_frames: frames to discard from a stream before keeping one.

    Raises:
        CaptureError: with an operator-readable reason.
    """
    url = (url or "").strip()
    if not url:
        raise CaptureError("Camera has no URL configured.")

    if url.startswith("file://"):
        return _grab_local(url[7:])
    if is_snapshot_url(url):
        return _grab_snapshot(url, timeout_s)
    if is_stream_url(url) or url.startswith(("http://", "https://")):
        return _with_deadline(
            lambda: _grab_stream(url, timeout_s, warmup_frames), timeout_s, url
        )
    return _grab_local(url)


def probe(url: str, timeout_s: float = 6.0) -> Dict:
    """Test a camera without keeping the frame — the 'Test feed' button.

    Never raises: a failure is a result the operator needs to see, not an
    exception in the middle of a settings screen.
    """
    started = time.time()
    try:
        frame = grab_frame(url, timeout_s=timeout_s, warmup_frames=2)
    except CaptureError as exc:
        return {"reachable": False, "message": str(exc)}
    except Exception as exc:  # unexpected decoder/driver failure
        return {"reachable": False, "message": f"Feed error: {exc}"}

    height, width = frame.shape[:2]
    return {
        "reachable": True,
        "message": "Feed is live.",
        "width": int(width),
        "height": int(height),
        "channels": int(frame.shape[2]) if frame.ndim == 3 else 1,
        "bit_depth": 16 if frame.dtype == np.uint16 else 8,
        "latency_ms": int((time.time() - started) * 1000),
    }


def grab_many(
    feeds: List[Tuple[str, str]],
    timeout_s: float = 8.0,
) -> Tuple[Dict[str, np.ndarray], Dict[str, str]]:
    """Grab one frame from each ``(key, url)`` feed, in parallel.

    The bands of a multispectral shot must belong to the same instant: pulling
    five RTSP streams one after another can spread a shot over several seconds
    of forward flight, which smears the band alignment the indices rely on.
    Threads overlap the network waits so the frames land within one another's
    jitter instead of one another's latency.

    Returns ``(frames, errors)`` — a partial result is still useful, so a dead
    band is reported rather than failing the whole shot.
    """
    from concurrent.futures import ThreadPoolExecutor

    frames: Dict[str, np.ndarray] = {}
    errors: Dict[str, str] = {}
    if not feeds:
        return frames, errors

    pool = ThreadPoolExecutor(max_workers=min(8, len(feeds)))
    try:
        futures = {
            pool.submit(grab_frame, url, timeout_s): key for key, url in feeds
        }
        for future, key in futures.items():
            try:
                # A hair over the per-grab budget: grab_frame already bounds
                # itself, and this only catches a worker that never started.
                frames[key] = future.result(timeout=timeout_s + 5.0)
            except CaptureError as exc:
                errors[key] = str(exc)
            except Exception as exc:  # pragma: no cover - driver dependent
                errors[key] = f"Feed error: {exc}"
    finally:
        # A dead camera must not hold the shot open for the live ones.
        pool.shutdown(wait=False)

    return frames, errors


def to_preview(frame: np.ndarray, max_edge: int = 900) -> np.ndarray:
    """8-bit BGR version of a frame, safe to write as a JPEG/PNG preview.

    A 16-bit band would otherwise render as near-black in the app, and a
    single-channel band has no colour at all — both are normalised here so the
    operator sees the picture the sensor actually took.
    """
    image = frame
    if image.dtype != np.uint8:
        finite = image[np.isfinite(image)]
        high = float(np.percentile(finite, 99.5)) if finite.size else 1.0
        low = float(np.percentile(finite, 0.5)) if finite.size else 0.0
        span = max(high - low, 1e-6)
        image = np.clip((image.astype(np.float32) - low) / span, 0.0, 1.0)
        image = (image * 255.0).astype(np.uint8)

    if image.ndim == 2:
        image = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    elif image.shape[2] == 4:
        image = cv2.cvtColor(image, cv2.COLOR_BGRA2BGR)

    height, width = image.shape[:2]
    longest = max(height, width)
    if longest > max_edge:
        scale = max_edge / float(longest)
        image = cv2.resize(
            image,
            (max(1, int(width * scale)), max(1, int(height * scale))),
            interpolation=cv2.INTER_AREA,
        )
    return image


def telemetry_geotag() -> Dict[str, Optional[float]]:
    """Position of the aircraft *now*, to stamp on the frame we just took.

    Returns all-None when no vehicle is connected — a frame without a fix is
    still worth keeping (the operator can analyse it), it just cannot be
    turned into spray waypoints later.
    """
    try:
        from app.mavlink import link

        snapshot = link.snapshot()
        telemetry = snapshot.get("telemetry") or {}
        if not snapshot.get("connected"):
            return {"lat": None, "lon": None, "alt_m": None, "heading_deg": None}
        return {
            "lat": telemetry.get("lat"),
            "lon": telemetry.get("lon"),
            "alt_m": telemetry.get("relative_alt_m"),
            "heading_deg": telemetry.get("heading_deg"),
        }
    except Exception:  # pragma: no cover - link is optional
        return {"lat": None, "lon": None, "alt_m": None, "heading_deg": None}
