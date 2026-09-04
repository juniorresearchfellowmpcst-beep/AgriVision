"""Continuous weed/disease analysis of a live drone feed.

The still-frame path already answers "what is wrong with *this* patch": the
operator presses Capture, the frame is stored, and
:class:`~app.services.field_scan_service.FieldScanService` scans it. That is
the right tool for a spot check and the wrong one for a pass over a field,
where the useful question is "what has the aircraft been flying over for the
last two minutes".

This module answers that. A sampler thread pulls one frame every few seconds
from the shared :mod:`app.capture.live` stream -- the same session the operator
is watching, so the camera is opened once -- runs the existing
:func:`app.ai.field_scan.scan_frame` on it, and keeps a rolling window of the
results plus the field-level aggregate over that window.

Two deliberate limits, both about being honest:

  * **Nothing here is recorded.** A live readout is a moving estimate from
    whatever happened to be under the camera a second ago, and writing every
    sample to the scan history would bury the deliberate captures an operator
    actually chose in thousands of drive-by frames. Recording stays where it
    was: press Capture, and the frame and its scan are stored.
  * **Frames are downscaled before scanning.** A 4K frame costs several
    seconds through the weed detector and the disease CNN, which would make
    the readout describe the field as it was well before it is displayed. The
    detectors work on colour and texture *ratios*, so a downscale changes the
    numbers very little and the latency a great deal.
"""

from __future__ import annotations

import logging
import threading
import time
from collections import deque
from typing import Any, Deque, Dict, List, Optional, Tuple

import cv2

from app.ai import field_scan
from app.capture import telemetry_geotag
from app.capture.live import hub

logger = logging.getLogger(__name__)

# How often a frame is pulled off the feed and scanned. Slower than it could
# be, on purpose: a drone at survey speed takes a few seconds to cover its own
# frame width, so sampling faster mostly re-scans the same ground.
DEFAULT_INTERVAL_S = 3.0
MIN_INTERVAL_S = 1.0
MAX_INTERVAL_S = 60.0

# Samples kept for the rolling aggregate. At the default interval this is
# about two minutes of flight -- long enough to describe a pass, short enough
# that the answer still refers to where the aircraft is now.
DEFAULT_WINDOW = 40
MAX_WINDOW = 200

# Every sample the analyser has taken since it started, kept *in memory only*
# so a finished survey can be summarised and clustered over the whole pass
# rather than over the last two minutes of it. This is not the recording the
# module docstring rules out: nothing here reaches the scan history, and it all
# dies with the process. The cap is a flight's worth at the default interval
# (roughly three hours) and exists so a forgotten analyser cannot grow without
# bound on a ground station left running for a week.
MAX_HISTORY = 4000

# Frames wider than this are shrunk before scanning. See the module docstring.
ANALYSIS_MAX_WIDTH = 960


def _fail(message: str, status: int = 400) -> Tuple[Dict[str, Any], int]:
    return {"status": "error", "message": message}, status


class LiveAnalyzer:
    """Samples one live feed on a timer and keeps a rolling scan window."""

    def __init__(
        self,
        camera_key: str,
        url: str,
        name: str = "",
        crop: Optional[str] = None,
        interval_s: float = DEFAULT_INTERVAL_S,
        window: int = DEFAULT_WINDOW,
        field_name: Optional[str] = None,
        target: str = "both",
    ):
        self.camera_key = str(camera_key)
        self.url = url
        self.name = name or self.camera_key
        self.crop = crop
        self.interval_s = interval_s
        self.field_name = field_name
        # disease | weed | both. Set when the operator flies a weed-detection
        # pass: skipping the disease CNN roughly halves the per-frame cost,
        # which is what keeps the readout describing where the aircraft is.
        self.target = target if target in field_scan.SCAN_TARGETS else "both"

        self._lock = threading.Lock()
        self._samples: Deque[Dict[str, Any]] = deque(maxlen=window)
        # The rolling window answers "what is under the aircraft now"; this
        # answers "what did the whole pass look like", which is what the
        # survey summary and the K-means hotspot map are built from.
        self._history: Deque[Dict[str, Any]] = deque(maxlen=MAX_HISTORY)
        self._latest: Optional[Dict[str, Any]] = None
        self._rolling: Optional[Dict[str, Any]] = None
        self._started_at = time.time()
        self._scanned = 0
        self._skipped = 0
        self._last_error: Optional[str] = None

        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None

    # -- lifecycle --------------------------------------------------------

    def start(self) -> "LiveAnalyzer":
        if self._thread is not None and self._thread.is_alive():
            return self
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run, name=f"liveanalysis-{self.camera_key}", daemon=True
        )
        self._thread.start()
        return self

    def stop(self) -> None:
        self._stop.set()

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    # -- sampling ---------------------------------------------------------

    def _run(self) -> None:
        # The analyser holds its own subscription for as long as it runs, so
        # the feed stays open even when the operator closes the video view --
        # a scan that stopped because someone looked away would be worse than
        # useless, because the summary would silently stop advancing.
        stream = hub.open(self.camera_key, self.url, self.name)
        seq = -1
        try:
            while not self._stop.is_set():
                started = time.monotonic()
                got = stream.latest(after_seq=seq, timeout=self.interval_s + 5.0)

                if got is None:
                    # The feed is down or reconnecting. Record the gap rather
                    # than re-scanning the last frame, which would report old
                    # ground as if the aircraft were still over it.
                    with self._lock:
                        self._skipped += 1
                        self._last_error = (
                            stream.status().get("last_error") or "No frame from the feed."
                        )
                    if self._stop.wait(1.0):
                        break
                    continue

                frame, seq, _stamp = got
                try:
                    self._scan(frame)
                except Exception as exc:  # pragma: no cover - detector dependent
                    logger.exception("live analysis failed on %s", self.camera_key)
                    with self._lock:
                        self._last_error = str(exc)

                # Interval measured from the *start* of the scan, so a slow
                # detector eats into the idle time instead of adding to it.
                elapsed = time.monotonic() - started
                if self._stop.wait(max(0.0, self.interval_s - elapsed)):
                    break
        finally:
            hub.release(stream)

    def _scan(self, frame) -> None:
        image = frame
        if image.shape[1] > ANALYSIS_MAX_WIDTH:
            scale = ANALYSIS_MAX_WIDTH / float(image.shape[1])
            image = cv2.resize(
                image,
                (ANALYSIS_MAX_WIDTH, max(1, int(image.shape[0] * scale))),
                interpolation=cv2.INTER_AREA,
            )

        result = field_scan.scan_frame(
            image,
            crop=self.crop,
            want_overlay=False,
            target=self.target,
            # Frames from the aircraft: several plants and the soil between
            # them, seen from altitude. The shipped classifier is a leaf model
            # and answers those confidently while being out of its domain, so
            # this path stays on the rules. See scan_frame's `framing`.
            framing="canopy",
        )
        result.pop("_overlay", None)
        if result.get("status") != "ok":
            with self._lock:
                self._skipped += 1
                self._last_error = result.get("message") or "Frame could not be scanned."
            return

        # Where the aircraft was when this frame was taken. Stamped on every
        # sample because aggregate() builds its hotspot list from exactly
        # these fields -- an unlocated bad frame cannot be flown back to.
        geotag = telemetry_geotag()
        result.update(
            {
                "frame_id": f"live_{int(time.time() * 1000)}",
                "captured_at": time.time(),
                "lat": geotag.get("lat"),
                "lon": geotag.get("lon"),
                "alt_m": geotag.get("alt_m"),
                "heading_deg": geotag.get("heading_deg"),
                "camera": self.name,
                "field_name": self.field_name,
            }
        )

        with self._lock:
            self._samples.append(result)
            self._history.append(result)
            self._latest = result
            self._scanned += 1
            self._last_error = None
            samples = list(self._samples)

        # Aggregate outside the lock: it is pure computation over a snapshot,
        # and holding the lock through it would stall the status endpoint.
        rolling = field_scan.aggregate(samples, crop=self.crop)
        with self._lock:
            self._rolling = rolling

    # -- readout ----------------------------------------------------------

    def status(self, include_latest: bool = True) -> Dict[str, Any]:
        with self._lock:
            latest = self._latest
            rolling = self._rolling
            scanned = self._scanned
            skipped = self._skipped
            last_error = self._last_error
            window = len(self._samples)

        stream = hub.get(self.camera_key)
        payload: Dict[str, Any] = {
            "camera_key": self.camera_key,
            "camera_name": self.name,
            "crop": self.crop,
            "target": self.target,
            "field_name": self.field_name,
            "running": self.running,
            "interval_s": self.interval_s,
            "window": window,
            "scanned": scanned,
            "skipped": skipped,
            "uptime_s": round(time.time() - self._started_at, 1),
            "last_error": last_error,
            "stream": stream.status() if stream is not None else None,
            "rolling": rolling,
        }
        if include_latest and latest is not None:
            payload["latest"] = _compact(latest)
        return payload

    def recent(self, limit: int = 20) -> List[Dict[str, Any]]:
        with self._lock:
            samples = list(self._samples)[-max(1, limit):]
        return [_compact(sample) for sample in samples]

    def history(self) -> List[Dict[str, Any]]:
        """Every sample since the analyser started, oldest first.

        Returned in full rather than compacted: the survey summary aggregates
        these through :func:`app.ai.field_scan.aggregate`, which reads fields
        the compact form drops.
        """
        with self._lock:
            return list(self._history)


def _compact(scan: Dict[str, Any]) -> Dict[str, Any]:
    """The parts of a scan worth sending on every poll.

    A full scan result carries the whole knowledge-base entry for the
    condition -- symptoms, management steps, what weather favours it. That is
    right for a scan the operator opened deliberately, and wasteful three
    times a minute over a field radio link, so the live readout sends the
    verdict and leaves the reference text to the detail endpoints.
    """
    disease = scan.get("disease") or {}
    weeds = scan.get("weeds") or {}
    return {
        "frame_id": scan.get("frame_id"),
        "captured_at": scan.get("captured_at"),
        "crop": scan.get("crop"),
        "crop_name": scan.get("crop_name"),
        "target": scan.get("target"),
        "is_healthy": scan.get("is_healthy"),
        "severity": scan.get("severity"),
        "disease": {
            "id": disease.get("id"),
            "name": disease.get("name"),
            "confidence": disease.get("confidence"),
            "source": disease.get("source"),
        },
        "weeds": {
            "weed_coverage": weeds.get("weed_coverage"),
            "vegetation_coverage": weeds.get("vegetation_coverage"),
            "pressure": weeds.get("pressure"),
            "patches": len(weeds.get("patches") or []),
        },
        "weed_species": scan.get("weed_species"),
        "actions": scan.get("actions"),
        "lat": scan.get("lat"),
        "lon": scan.get("lon"),
        "alt_m": scan.get("alt_m"),
        "heading_deg": scan.get("heading_deg"),
    }


class LiveAnalysisManager:
    """The analysers currently running, one per camera at most."""

    def __init__(self):
        self._analyzers: Dict[str, LiveAnalyzer] = {}
        self._lock = threading.Lock()

    def start(
        self,
        camera_key: str,
        url: str,
        name: str = "",
        crop: Optional[str] = None,
        interval_s: float = DEFAULT_INTERVAL_S,
        window: int = DEFAULT_WINDOW,
        field_name: Optional[str] = None,
        target: str = "both",
    ) -> LiveAnalyzer:
        key = str(camera_key)
        with self._lock:
            existing = self._analyzers.get(key)
            if existing is not None and existing.running:
                # Re-starting an already-running analyser is how the app
                # changes the crop or the detection target mid-pass. Keep the
                # window: the frames already scanned are still the same ground.
                existing.crop = crop
                existing.interval_s = interval_s
                existing.field_name = field_name
                existing.target = (
                    target if target in field_scan.SCAN_TARGETS else existing.target
                )
                return existing
            analyzer = LiveAnalyzer(
                key, url, name, crop, interval_s, window, field_name, target
            )
            self._analyzers[key] = analyzer
        return analyzer.start()

    def stop(self, camera_key: str) -> bool:
        with self._lock:
            analyzer = self._analyzers.pop(str(camera_key), None)
        if analyzer is None:
            return False
        analyzer.stop()
        return True

    def get(self, camera_key: str) -> Optional[LiveAnalyzer]:
        return self._analyzers.get(str(camera_key))

    def status(self) -> List[Dict[str, Any]]:
        with self._lock:
            analyzers = list(self._analyzers.items())
            for key, analyzer in analyzers:
                if not analyzer.running:
                    self._analyzers.pop(key, None)
        return [analyzer.status() for _key, analyzer in analyzers if analyzer.running]

    def shutdown(self) -> None:
        with self._lock:
            analyzers = list(self._analyzers.values())
            self._analyzers.clear()
        for analyzer in analyzers:
            analyzer.stop()


manager = LiveAnalysisManager()


class LiveAnalysisService:
    """Service-layer wrapper, returning ``(response, status)`` like the rest."""

    @staticmethod
    def start(payload: Optional[Dict], camera) -> Tuple[Dict[str, Any], int]:
        payload = payload if isinstance(payload, dict) else {}

        try:
            interval = float(payload.get("interval_s", DEFAULT_INTERVAL_S))
        except (TypeError, ValueError):
            return _fail("interval_s must be a number of seconds.")
        if not MIN_INTERVAL_S <= interval <= MAX_INTERVAL_S:
            return _fail(
                f"interval_s must be between {MIN_INTERVAL_S:.0f} and "
                f"{MAX_INTERVAL_S:.0f} seconds."
            )

        try:
            window = int(payload.get("window", DEFAULT_WINDOW))
        except (TypeError, ValueError):
            return _fail("window must be a whole number of frames.")
        window = max(1, min(MAX_WINDOW, window))

        if camera.role != "rgb":
            return _fail(
                "Live weed and disease analysis reads the ordinary RGB camera. "
                "A multispectral band feeds the spray prescription instead -- "
                "capture a shot and prescribe from it."
            )

        target = str(payload.get("target") or "both").strip().lower()
        if target not in field_scan.SCAN_TARGETS:
            return _fail(
                "target must be one of: "
                + ", ".join(field_scan.SCAN_TARGETS)
                + ". Use 'weed' to fly a weed-detection pass."
            )

        analyzer = manager.start(
            camera_key=str(camera.id),
            url=camera.url,
            name=camera.name,
            crop=payload.get("crop") or None,
            interval_s=interval,
            window=window,
            field_name=payload.get("field_name") or None,
            target=target,
        )
        return {
            "status": "ok",
            "message": f"Watching {camera.name}.",
            "analysis": analyzer.status(),
        }, 200

    @staticmethod
    def stop(camera_key: str) -> Tuple[Dict[str, Any], int]:
        if not manager.stop(camera_key):
            return _fail("Nothing is analysing that camera.", 404)
        return {"status": "ok", "message": "Live analysis stopped."}, 200

    @staticmethod
    def status(camera_key: Optional[str] = None) -> Tuple[Dict[str, Any], int]:
        if camera_key:
            analyzer = manager.get(camera_key)
            if analyzer is None:
                return {
                    "status": "ok",
                    "running": False,
                    "analysis": None,
                }, 200
            return {"status": "ok", "running": True, "analysis": analyzer.status()}, 200
        return {"status": "ok", "analyses": manager.status()}, 200

    @staticmethod
    def recent(camera_key: str, limit: int = 20) -> Tuple[Dict[str, Any], int]:
        analyzer = manager.get(camera_key)
        if analyzer is None:
            return _fail("Nothing is analysing that camera.", 404)
        return {"status": "ok", "frames": analyzer.recent(limit)}, 200

    @staticmethod
    def history(camera_key: str) -> List[Dict[str, Any]]:
        """Every sample this analyser has taken, for the survey summary.

        Returns a plain list rather than a ``(response, status)`` pair: the
        caller is :mod:`app.services.survey_service`, not a route, and an
        analyser that is not running is not an error there -- it is a survey
        whose pass has already ended.
        """
        analyzer = manager.get(camera_key)
        return analyzer.history() if analyzer is not None else []
