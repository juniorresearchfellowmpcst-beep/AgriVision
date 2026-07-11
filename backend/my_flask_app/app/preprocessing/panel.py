"""Locating the calibration (reference) panel inside a panel photo.

The reflectance panel is a flat, spectrally-uniform grey target photographed
right before/after a flight. To turn raw pixels into reflectance we need the
mean panel signal per band, which means finding the panel's pixels.

Two strategies are supported:
  * explicit ROI  -> you pass (x, y, w, h); most reliable.
  * auto-detect   -> find the largest bright, uniform, quadrilateral region.
Auto-detect is best-effort; always sanity-check it for quantitative work.
"""

from typing import Optional, Tuple

import cv2
import numpy as np

from .io import to_uint8


def _shrink_roi(x: int, y: int, w: int, h: int, frac: float) -> Tuple[int, int, int, int]:
    """Trim `frac` off each side so we sample the panel centre, not its edges."""
    dx, dy = int(w * frac), int(h * frac)
    return x + dx, y + dy, max(1, w - 2 * dx), max(1, h - 2 * dy)


def detect_panel_roi(band_img: np.ndarray, shrink: float = 0.15) -> Optional[Tuple[int, int, int, int]]:
    """Auto-detect the panel ROI in a single band. Returns (x, y, w, h) or None.

    Heuristic: threshold to the bright, flat region, keep large 4-corner-ish
    contours, and pick the one with the most uniform interior (lowest relative
    standard deviation) — panels are matte and uniform, unlike the scene.
    """
    u8 = to_uint8(band_img)
    blur = cv2.GaussianBlur(u8, (5, 5), 0)

    # Otsu isolates the bright panel from a typically darker background.
    _, mask = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    img_area = band_img.shape[0] * band_img.shape[1]
    best = None
    best_uniformity = np.inf

    for cnt in contours:
        area = cv2.contourArea(cnt)
        # Panel should be a meaningful but not scene-filling blob.
        if area < 0.002 * img_area or area > 0.6 * img_area:
            continue

        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.04 * peri, True)
        if len(approx) < 4 or not cv2.isContourConvex(approx):
            continue

        x, y, w, h = cv2.boundingRect(approx)
        aspect = w / float(h) if h else 0
        if not (0.4 < aspect < 2.5):  # panels are roughly square-ish
            continue

        sx, sy, sw, sh = _shrink_roi(x, y, w, h, shrink)
        patch = band_img[sy:sy + sh, sx:sx + sw]
        if patch.size == 0:
            continue

        mean = float(patch.mean())
        if mean <= 0:
            continue
        # Relative std: how flat is the interior? Lower is more panel-like.
        uniformity = float(patch.std()) / mean
        if uniformity < best_uniformity:
            best_uniformity = uniformity
            best = (sx, sy, sw, sh)

    return best


def panel_signal(
    band_img: np.ndarray,
    roi: Optional[Tuple[int, int, int, int]],
    shrink: float,
    saturation_dn: float,
) -> Tuple[float, dict]:
    """Mean panel signal for one band, ignoring saturated/edge pixels.

    Returns (mean_signal, info) where info records the ROI used, the pixel
    count and whether the sample looked saturated — surfaced in the report so a
    bad panel capture is caught, not silently trusted.
    """
    if roi is None:
        roi = detect_panel_roi(band_img, shrink)
        auto = True
    else:
        # Caller-supplied ROI is still shrunk to avoid panel edges.
        roi = _shrink_roi(*roi, shrink)
        auto = False

    if roi is None:
        raise ValueError(
            "Calibration panel could not be located automatically; "
            "pass an explicit panel ROI (x, y, w, h)."
        )

    x, y, w, h = roi
    patch = band_img[y:y + h, x:x + w]
    if patch.size == 0:
        raise ValueError(f"Panel ROI {roi} is empty for this image.")

    valid = patch[patch < saturation_dn]
    saturated_frac = 1.0 - (valid.size / patch.size)
    sample = valid if valid.size else patch

    info = {
        "roi": [int(x), int(y), int(w), int(h)],
        "auto_detected": auto,
        "pixels": int(sample.size),
        "saturated_fraction": round(float(saturated_frac), 4),
        "mean_dn": round(float(sample.mean()), 3),
    }
    return float(sample.mean()), info
