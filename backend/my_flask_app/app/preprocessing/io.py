"""Loading and saving of per-band multispectral imagery.

Multispectral cameras usually store one single-band file per band (16-bit
GeoTIFF/TIFF). These helpers read those into float32 arrays, keep the band
order stable, and write out results as TIFF (data) or PNG (previews).
"""

import os
from typing import Dict, List, Tuple

import cv2
import numpy as np


# Extensions we accept as raw band images.
_IMAGE_EXTS = (".tif", ".tiff", ".png", ".jpg", ".jpeg")


def read_band(path: str) -> np.ndarray:
    """Read a single-band image as a float32 2-D array, preserving bit depth.

    Raises FileNotFoundError if the path is missing and ValueError if the file
    cannot be decoded as an image.
    """
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Band image not found: {path}")

    # ANYDEPTH keeps 16-bit data; UNCHANGED avoids implicit BGR conversion.
    img = cv2.imread(path, cv2.IMREAD_ANYDEPTH | cv2.IMREAD_UNCHANGED)
    if img is None:
        raise ValueError(f"Could not decode image: {path}")

    # If a multi-channel file sneaks in, collapse to luminance so downstream
    # code can always assume a single band.
    if img.ndim == 3:
        img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    return img.astype(np.float32)


def read_band_stack(paths: Dict[str, str], band_order: List[str]) -> "BandStack":
    """Read a dict of {band_name: path} into an ordered BandStack."""
    missing = [b for b in band_order if b not in paths]
    if missing:
        raise ValueError(f"Missing band image(s) for: {', '.join(missing)}")

    bands = [read_band(paths[name]) for name in band_order]

    shapes = {b.shape for b in bands}
    if len(shapes) != 1:
        # Bands from separate lenses can differ by a pixel or two; resize the
        # rest to the reference band's shape before stacking.
        ref_shape = bands[0].shape
        bands = [
            b if b.shape == ref_shape
            else cv2.resize(b, (ref_shape[1], ref_shape[0]), interpolation=cv2.INTER_AREA)
            for b in bands
        ]

    return BandStack(np.stack(bands, axis=0), list(band_order))


class BandStack:
    """An ordered stack of single-band images: shape (n_bands, H, W)."""

    def __init__(self, data: np.ndarray, band_names: List[str]):
        if data.ndim != 3:
            raise ValueError("BandStack data must be (n_bands, H, W)")
        if data.shape[0] != len(band_names):
            raise ValueError("band_names length must match number of bands")
        self.data = data.astype(np.float32)
        self.band_names = list(band_names)

    @property
    def shape(self) -> Tuple[int, int, int]:
        return self.data.shape

    def index(self, band: str) -> int:
        if band not in self.band_names:
            raise KeyError(f"Band '{band}' not in stack {self.band_names}")
        return self.band_names.index(band)

    def band(self, band: str) -> np.ndarray:
        return self.data[self.index(band)]

    def copy(self) -> "BandStack":
        return BandStack(self.data.copy(), list(self.band_names))


def save_stack(stack: "BandStack", out_dir: str, prefix: str = "band") -> Dict[str, str]:
    """Write each band of the stack to a 32-bit float TIFF. Returns {band: path}."""
    os.makedirs(out_dir, exist_ok=True)
    written: Dict[str, str] = {}
    for name in stack.band_names:
        path = os.path.join(out_dir, f"{prefix}_{name}.tif")
        cv2.imwrite(path, stack.band(name).astype(np.float32))
        written[name] = path
    return written


def to_uint8(arr: np.ndarray) -> np.ndarray:
    """Robustly scale any array to 0..255 uint8 for previews/feature matching.

    Uses 2nd/98th percentile stretch so a few hot or dead pixels don't crush
    the contrast of the rest of the image.
    """
    finite = arr[np.isfinite(arr)]
    if finite.size == 0:
        return np.zeros(arr.shape, dtype=np.uint8)
    lo, hi = np.percentile(finite, (2, 98))
    if hi <= lo:
        hi = lo + 1.0
    scaled = np.clip((arr - lo) / (hi - lo), 0.0, 1.0)
    return (scaled * 255.0).astype(np.uint8)


def save_false_color(
    stack: "BandStack",
    out_path: str,
    rgb_bands: Tuple[str, str, str] = ("nir", "red", "green"),
) -> str:
    """Write a false-colour composite PNG for quick visual QC.

    Default (NIR, Red, Green) is the classic colour-infrared view where healthy
    vegetation appears bright red.
    """
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    chans = [to_uint8(stack.band(b)) for b in rgb_bands]
    # OpenCV writes BGR, so reverse the RGB channel order.
    bgr = np.dstack(list(reversed(chans)))
    cv2.imwrite(out_path, bgr)
    return out_path


def discover_capture(directory: str, band_order: List[str]) -> Dict[str, str]:
    """Best-effort match of band files in a folder by band name in the filename.

    Looks for each band keyword (and common aliases) inside file names, e.g.
    'IMG_0001_2.tif' containing 'green'. Returns {band: path} for what it finds.
    """
    aliases = {
        "blue": ["blue", "_1", "b1"],
        "green": ["green", "_2", "b2"],
        "red": ["red", "_3", "b3"],
        "red_edge": ["red_edge", "rededge", "re", "_4", "b4"],
        "nir": ["nir", "_5", "b5"],
    }
    files = [
        os.path.join(directory, f)
        for f in os.listdir(directory)
        if f.lower().endswith(_IMAGE_EXTS)
    ]
    found: Dict[str, str] = {}
    for band in band_order:
        keys = aliases.get(band, [band])
        for f in files:
            name = os.path.basename(f).lower()
            if any(k in name for k in keys):
                found[band] = f
                break
    return found
