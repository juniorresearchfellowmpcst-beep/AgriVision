"""Live camera capture from the aircraft.

Grabs stills from the drone's two camera systems — the multispectral band rig
and the ordinary RGB IP camera — geotags them from MAVLink telemetry, and
stores them in a per-flight layout the analysis modules can read:

    app.capture.sources  — bytes off the wire -> numpy frame
    app.capture.store    — frame -> file on disk (+ 8-bit preview)
    app.capture.live     — camera held open -> newest frame, continuously

Downstream, a multispectral shot feeds :mod:`app.spray` (K-means prescription)
and an RGB frame feeds :mod:`app.ai.field_scan` (weed + disease CNN). The live
side of that same feed is what the operator watches and what
:mod:`app.services.live_analysis` samples while the aircraft is flying.
"""

from .live import (
    MJPEG_BOUNDARY,
    LiveStream,
    StreamHub,
    encode_jpeg,
    hub,
    mjpeg_stream,
)
from .sources import (
    CaptureError,
    DEFAULT_WARMUP_FRAMES,
    grab_frame,
    grab_many,
    is_snapshot_url,
    is_stream_url,
    probe,
    telemetry_geotag,
    to_preview,
)
from .store import (
    absolute,
    band_paths_for_shot,
    new_session_id,
    new_shot_id,
    safe_key,
    save_frame,
    shot_dir,
    url_for,
)

__all__ = [
    "CaptureError",
    "DEFAULT_WARMUP_FRAMES",
    "LiveStream",
    "MJPEG_BOUNDARY",
    "StreamHub",
    "encode_jpeg",
    "hub",
    "mjpeg_stream",
    "grab_frame",
    "grab_many",
    "is_snapshot_url",
    "is_stream_url",
    "probe",
    "telemetry_geotag",
    "to_preview",
    "absolute",
    "band_paths_for_shot",
    "new_session_id",
    "new_shot_id",
    "safe_key",
    "save_frame",
    "shot_dir",
    "url_for",
]
