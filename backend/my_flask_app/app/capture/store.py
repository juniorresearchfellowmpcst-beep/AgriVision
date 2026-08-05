"""On-disk layout for captured drone frames.

Everything a flight produces lands under one root (``instance/captures``) in a
shape the rest of the app can navigate without a database round-trip::

    captures/
      <session_id>/                  one flight / one field visit
        <shot_id>/                   one trigger of the shutter
          nir.png                    multispectral band, full bit depth
          red.png
          ...
          nir_preview.jpg            8-bit, app-viewable
          rgb.png                    the IP camera's frame (role "rgb")

The band files keep their original depth because the vegetation indices need
it; the ``_preview.jpg`` beside each one is what the phone downloads. Shot ids
are time-ordered so a directory listing is a flight timeline.
"""

from __future__ import annotations

import os
import re
import time
import uuid
from typing import Dict, Optional

import cv2
import numpy as np

from .sources import to_preview

# Band/role keys are used as filenames, so keep them boring.
_SAFE_KEY = re.compile(r"[^a-z0-9_\-]+")


def safe_key(value: str, fallback: str = "frame") -> str:
    """Normalise a band/role name into something safe to put in a path."""
    cleaned = _SAFE_KEY.sub("_", str(value or "").strip().lower()).strip("_")
    return cleaned or fallback


def new_session_id(prefix: str = "sess") -> str:
    """Time-ordered id so sessions sort chronologically in a listing."""
    return f"{prefix}_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"


def new_shot_id() -> str:
    # Millisecond resolution: a low-pace mission can trigger several times a
    # second, and two shots sharing an id would overwrite each other's bands.
    return f"shot_{int(time.time() * 1000)}_{uuid.uuid4().hex[:4]}"


def shot_dir(base_dir: str, session_id: str, shot_id: str) -> str:
    return os.path.join(base_dir, safe_key(session_id, "session"), safe_key(shot_id, "shot"))


def save_frame(
    frame: np.ndarray,
    base_dir: str,
    session_id: str,
    shot_id: str,
    key: str,
    write_preview: bool = True,
) -> Dict[str, str]:
    """Write one frame (plus its preview) and return both relative paths.

    Paths are returned *relative to* ``base_dir`` because that is what gets
    stored and later turned into a URL — an absolute path in the database
    would break the moment the deployment moved.
    """
    directory = shot_dir(base_dir, session_id, shot_id)
    os.makedirs(directory, exist_ok=True)

    name = safe_key(key)
    # PNG, not JPEG: lossless and 16-bit capable. A JPEG'd NIR band would hand
    # the index maths compression artefacts as if they were canopy structure.
    path = os.path.join(directory, f"{name}.png")
    if not cv2.imwrite(path, frame):
        raise IOError(f"Could not write captured frame to {path}")

    result = {"path": _relative(path, base_dir)}

    if write_preview:
        preview_path = os.path.join(directory, f"{name}_preview.jpg")
        if cv2.imwrite(preview_path, to_preview(frame)):
            result["preview"] = _relative(preview_path, base_dir)

    return result


def _relative(path: str, base_dir: str) -> str:
    try:
        return os.path.relpath(path, base_dir).replace(os.sep, "/")
    except ValueError:  # different drive on Windows
        return path.replace(os.sep, "/")


def absolute(relpath: str, base_dir: str) -> str:
    """Turn a stored relative path back into a filesystem path."""
    return os.path.join(base_dir, *str(relpath).split("/"))


def band_paths_for_shot(base_dir: str, session_id: str, shot_id: str) -> Dict[str, str]:
    """Map ``{band: absolute path}`` for a stored multispectral shot.

    This is the handover point to the analysis pipeline, which reads bands
    from disk. Previews are skipped — they are 8-bit and lossy.
    """
    directory = shot_dir(base_dir, session_id, shot_id)
    if not os.path.isdir(directory):
        return {}

    bands: Dict[str, str] = {}
    for entry in sorted(os.listdir(directory)):
        name, ext = os.path.splitext(entry)
        if ext.lower() not in (".png", ".tif", ".tiff") or name.endswith("_preview"):
            continue
        bands[name] = os.path.join(directory, entry)
    return bands


def url_for(relpath: Optional[str], url_prefix: str) -> Optional[str]:
    """Public URL for a stored frame, or None when there is nothing to serve."""
    if not relpath:
        return None
    return f"{url_prefix.rstrip('/')}/{relpath}"
