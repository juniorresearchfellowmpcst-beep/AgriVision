"""Weed detection in an RGB canopy frame from a low-pace mission.

The hard part of weed detection from the air is not finding plants — it is
deciding which plants are the *crop*. A drone photo of a weedy field is mostly
green either way. Two signals separate them, and this module uses whichever
the frame actually supports:

**1. Row geometry (preferred).** A sown crop grows in lines; weeds do not
respect them. So: segment vegetation, find the direction the rows run, and
call the green between the rows weed. This is the same logic a farmer uses
walking a field, and it works regardless of species.

**2. Appearance clustering (fallback).** Broadcast-sown wheat or transplanted
paddy has no usable row signal. There the module clusters the vegetation into
two groups by colour and texture and treats the minority group as weeds — a
weaker inference, reported as such, with the confidence dropped and a note
saying why.

Both run on plain OpenCV/NumPy, so the feature works with no model download.
A trained segmentation/classification model can be layered on top through
:mod:`app.ai.crop_model` to name the weed species; the coverage measurement
below is what feeds the decision either way.
"""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional, Tuple

import cv2
import numpy as np

# Analysis resolution. Big enough to resolve a row gap, small enough that a
# 90-angle row search is a few milliseconds.
_MAX_EDGE = 720
_ROW_SEARCH_EDGE = 256

# Autocorrelation strength above which we believe the frame really has rows.
# Below it, a "period" is just noise, and acting on it would label random
# stripes of crop as weeds.
_ROW_PERIODICITY_MIN = 0.22

# A weed blob smaller than this share of the frame is speckle, not a patch.
_MIN_PATCH_FRACTION = 0.0004


def excess_green(img_bgr: np.ndarray) -> np.ndarray:
    """Excess Green (ExG = 2G − R − B), the classic vegetation index for RGB.

    Normalising the channels by their sum first is what makes it survive an
    exposure change between frames: it measures *how green* a pixel is
    relative to its own brightness, not how bright the green channel is.
    """
    img = img_bgr.astype(np.float32)
    if img.ndim == 2:
        img = cv2.cvtColor(img.astype(np.uint8), cv2.COLOR_GRAY2BGR).astype(np.float32)
    blue, green, red = img[:, :, 0], img[:, :, 1], img[:, :, 2]
    total = blue + green + red + 1e-6
    return (2.0 * green - red - blue) / total


def vegetation_mask(img_bgr: np.ndarray) -> Tuple[np.ndarray, float]:
    """Binary vegetation mask plus the share of the frame it covers."""
    exg = excess_green(img_bgr)
    scaled = np.clip((exg + 1.0) * 127.5, 0, 255).astype(np.uint8)

    # Otsu adapts to the soil/canopy mix in this particular frame; a fixed ExG
    # cut-off that works on black cotton soil fails on light alluvium.
    _threshold, mask = cv2.threshold(scaled, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

    # Otsu will still split *something* out of a bare-soil frame, so require
    # the pixels it chose to be genuinely green before believing them.
    mask[exg < 0.02] = 0

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=1)

    coverage = float(np.count_nonzero(mask)) / float(mask.size or 1)
    return mask, coverage


def _resize(img: np.ndarray, max_edge: int = _MAX_EDGE) -> np.ndarray:
    height, width = img.shape[:2]
    longest = max(height, width)
    if longest <= max_edge:
        return img
    scale = max_edge / float(longest)
    return cv2.resize(
        img, (max(1, int(width * scale)), max(1, int(height * scale))),
        interpolation=cv2.INTER_AREA,
    )


def _rotate(img: np.ndarray, angle_deg: float) -> Tuple[np.ndarray, np.ndarray]:
    """Rotate about the centre onto a canvas big enough to keep every pixel."""
    height, width = img.shape[:2]
    centre = (width / 2.0, height / 2.0)
    matrix = cv2.getRotationMatrix2D(centre, angle_deg, 1.0)

    cos, sin = abs(matrix[0, 0]), abs(matrix[0, 1])
    new_width = int(height * sin + width * cos)
    new_height = int(height * cos + width * sin)
    matrix[0, 2] += (new_width / 2.0) - centre[0]
    matrix[1, 2] += (new_height / 2.0) - centre[1]

    rotated = cv2.warpAffine(
        img, matrix, (new_width, new_height), flags=cv2.INTER_NEAREST, borderValue=0
    )
    return rotated, matrix


def _periodicity(profile: np.ndarray) -> Tuple[float, int]:
    """Strength and period of the strongest repeat in a 1-D profile.

    Crop rows make the column-sum profile periodic; weeds and bare ground do
    not. Normalised autocorrelation is the cheapest way to ask "does this
    repeat, and how often" without committing to a peak-finding heuristic.
    """
    values = profile.astype(np.float64)
    values = values - values.mean()
    if not np.any(values):
        return 0.0, 0

    correlation = np.correlate(values, values, mode="full")[len(values) - 1:]
    zero_lag = correlation[0]
    if zero_lag <= 0:
        return 0.0, 0
    correlation = correlation / zero_lag

    # Ignore lags too small to be a row spacing, and too large to repeat.
    low = max(4, len(values) // 60)
    high = max(low + 1, len(values) // 3)
    window = correlation[low:high]
    if window.size == 0:
        return 0.0, 0

    best = int(np.argmax(window))
    return float(window[best]), int(best + low)


def _column_profile(mask: np.ndarray, angle_deg: float):
    """Vegetation *fraction* per column after rotating the mask.

    Rotating onto a bigger canvas pads the corners with zeros, so a raw column
    sum traces the trapezoid of the rotated rectangle rather than the crop.
    That artefact is smooth and strongly autocorrelated — enough to invent
    convincing "rows" in a perfectly uniform canopy. Dividing by the number of
    genuinely in-frame pixels in each column, and dropping the columns that
    are mostly padding, removes it entirely.

    Returns ``(profile, matrix, keep, rotated_shape)``; ``profile`` is ``None``
    when too little of the frame survives to say anything.
    """
    rotated, matrix = _rotate(mask, angle_deg)
    valid, _valid_matrix = _rotate(np.full(mask.shape, 255, dtype=np.uint8), angle_deg)

    valid_counts = (valid > 0).sum(axis=0).astype(np.float32)
    keep = valid_counts >= 0.6 * max(valid_counts.max(), 1)
    if int(keep.sum()) < 16:
        return None, matrix, keep, rotated.shape

    coverage = (rotated > 0).sum(axis=0).astype(np.float32)
    profile = np.zeros_like(coverage)
    profile[keep] = coverage[keep] / np.maximum(valid_counts[keep], 1.0)
    return profile, matrix, keep, rotated.shape


def find_rows(mask: np.ndarray) -> Dict[str, Any]:
    """Direction and spacing of the crop rows, if the frame has any.

    Searches rotation angles and keeps the one whose across-row profile
    repeats most strongly. Returns ``found=False`` when nothing repeats
    convincingly — which is the honest answer for a broadcast-sown crop.
    """
    small = _resize(mask, _ROW_SEARCH_EDGE)

    best = {"score": 0.0, "angle": 0.0, "period_px": 0}
    for angle in range(0, 180, 3):
        profile, _matrix, keep, _shape = _column_profile(small, angle)
        if profile is None:
            continue
        # If the rows now run vertically, this profile is a comb of peaks.
        profile = profile[keep]
        if profile.size < 16:
            continue
        score, period = _periodicity(profile)
        if score > best["score"]:
            best = {"score": score, "angle": float(angle), "period_px": period}

    found = best["score"] >= _ROW_PERIODICITY_MIN and best["period_px"] > 0
    # Scale the period back up to the working resolution.
    scale = mask.shape[1] / float(small.shape[1] or 1)
    return {
        "found": bool(found),
        "angle_deg": best["angle"],
        "row_spacing_px": round(best["period_px"] * scale, 1) if found else None,
        "strength": round(best["score"], 3),
    }


def _row_band_mask(
    mask: np.ndarray, angle_deg: float, row_spacing_px: Optional[float] = None
) -> Optional[np.ndarray]:
    """Mask of the crop rows themselves, in the original frame's geometry."""
    profile, matrix, keep, rotated_shape = _column_profile(mask, angle_deg)
    if profile is None or profile.max() <= 0:
        return None

    normalised = (profile / profile.max() * 255).astype(np.uint8)
    # Otsu on the profile splits "column is on a row" from "column is between
    # rows" without hard-coding how wide a row is — which varies with crop,
    # spacing and how high the drone was flying.
    threshold, _ = cv2.threshold(
        normalised[keep], 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
    )
    # Strictly greater, matching OpenCV's own THRESH_BINARY convention. On a
    # cleanly bimodal profile (every column either all crop or all soil) Otsu
    # returns 0 — every split separates the classes equally well, so it takes
    # the first — and `>= 0` would then call the entire frame a crop row.
    on_row = (normalised > threshold) & keep
    if on_row.all() or not on_row.any():
        return None

    # Widen each band by a couple of pixels. A crop row has a soft edge, and
    # a rotation rounded to whole pixels shifts it by one more — without the
    # margin the row's own outer leaves come back as "vegetation between the
    # rows", which is the crop being reported as a weed. Keep it small: a
    # generous margin swallows the inter-row weeds it exists to expose.
    margin = max(1, int(round((row_spacing_px or 0) * 0.04)))
    widened = cv2.dilate(
        on_row.astype(np.uint8).reshape(1, -1),
        cv2.getStructuringElement(cv2.MORPH_RECT, (2 * margin + 1, 1)),
    ).ravel().astype(bool)
    # Padding columns stay out no matter how far the dilation reached.
    widened &= keep

    bands = np.zeros(rotated_shape, dtype=np.uint8)
    bands[:, widened] = 255

    # Warp the band mask back into the original frame.
    inverse = cv2.invertAffineTransform(matrix)
    return cv2.warpAffine(
        bands, inverse, (mask.shape[1], mask.shape[0]),
        flags=cv2.INTER_NEAREST, borderValue=0,
    )


def _appearance_split(img_bgr: np.ndarray, veg_mask: np.ndarray) -> Optional[np.ndarray]:
    """Fallback: cluster vegetation by colour + texture, minority = weeds.

    Used only when there is no row structure to exploit. Two clusters over
    (hue, saturation, local texture); the smaller one is taken as the weed
    group, because a crop that fails to be the majority of its own field is
    not a scenario worth optimising for. Returns ``None`` when the split is
    too even to mean anything.
    """
    pixels = veg_mask > 0
    count = int(np.count_nonzero(pixels))
    if count < 200:
        return None

    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    grey = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    # Local standard deviation as a cheap texture measure: a fine grass weed
    # and a broad crop leaf differ here even when their colour does not.
    blurred = cv2.blur(grey.astype(np.float32), (7, 7))
    variance = cv2.blur((grey.astype(np.float32) - blurred) ** 2, (7, 7))
    texture = np.sqrt(np.maximum(variance, 0))

    features = np.stack(
        [
            hsv[:, :, 0].astype(np.float32)[pixels] / 179.0,
            hsv[:, :, 1].astype(np.float32)[pixels] / 255.0,
            np.clip(texture[pixels] / 64.0, 0, 1),
        ],
        axis=1,
    ).astype(np.float32)

    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5)
    cv2.setRNGSeed(42)
    _compactness, labels, _centres = cv2.kmeans(
        features, 2, None, criteria, 3, cv2.KMEANS_PP_CENTERS
    )
    labels = labels.ravel()

    minority = 0 if np.count_nonzero(labels == 0) < np.count_nonzero(labels == 1) else 1
    minority_share = np.count_nonzero(labels == minority) / float(count)
    # A near-even split says the two groups are not crop-vs-weed, just two
    # halves of one canopy. Refuse rather than invent a number.
    if minority_share > 0.42:
        return None

    weed = np.zeros_like(veg_mask)
    weed[pixels] = np.where(labels == minority, 255, 0).astype(np.uint8)
    return weed


def _significant_patches(
    weed_mask: np.ndarray, frame_area: int
) -> Tuple[np.ndarray, List[Dict[str, Any]]]:
    """Drop speckle, and report coverage from what is left.

    Measuring coverage on the raw mask counts every one-pixel sliver along a
    row edge as weed, which is how a spotless field ends up reading as 8%
    weedy. Coverage and the patch list must come from the *same* filtered
    mask, or the app shows a number no listed patch accounts for.
    """
    min_area = max(30, int(frame_area * _MIN_PATCH_FRACTION))
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(
        (weed_mask > 0).astype(np.uint8), connectivity=8
    )

    kept = np.zeros_like(weed_mask)
    patches = []
    for i in range(1, count):
        area = int(stats[i, cv2.CC_STAT_AREA])
        if area < min_area:
            continue
        kept[labels == i] = 255
        patches.append({
            "pixels": area,
            "frame_fraction": round(area / float(frame_area), 4),
            "centroid_px": [round(float(centroids[i][0]), 1), round(float(centroids[i][1]), 1)],
            "bbox_px": [
                int(stats[i, cv2.CC_STAT_LEFT]), int(stats[i, cv2.CC_STAT_TOP]),
                int(stats[i, cv2.CC_STAT_WIDTH]), int(stats[i, cv2.CC_STAT_HEIGHT]),
            ],
        })

    patches.sort(key=lambda p: p["pixels"], reverse=True)
    # The biggest few are what an operator will act on; the mask still carries
    # every kept patch, so the coverage figure stays complete.
    return kept, patches[:25]


def render_overlay(
    img_bgr: np.ndarray, veg_mask: np.ndarray, weed_mask: np.ndarray
) -> np.ndarray:
    """Frame with crop tinted green and weeds tinted red, for the app."""
    overlay = img_bgr.copy()
    if overlay.ndim == 2:
        overlay = cv2.cvtColor(overlay, cv2.COLOR_GRAY2BGR)

    crop_only = cv2.bitwise_and(veg_mask, cv2.bitwise_not(weed_mask))
    tint = overlay.copy()
    tint[crop_only > 0] = (80, 190, 80)
    tint[weed_mask > 0] = (60, 60, 230)
    return cv2.addWeighted(tint, 0.45, overlay, 0.55, 0)


def detect(img_bgr: np.ndarray, crop: Optional[str] = None) -> Dict[str, Any]:
    """Measure weed pressure in one canopy frame.

    Returns coverage, pressure level, patches, the method that produced them,
    and an overlay image (as an array — the caller decides where to write it).
    """
    from .weed_kb import likely_weeds, pressure_for

    image = _resize(img_bgr if img_bgr.ndim == 3 else cv2.cvtColor(img_bgr, cv2.COLOR_GRAY2BGR))
    frame_area = image.shape[0] * image.shape[1]

    veg_mask, veg_coverage = vegetation_mask(image)
    if veg_coverage < 0.02:
        return {
            "status": "ok",
            "vegetation_coverage": round(veg_coverage, 4),
            "weed_coverage": 0.0,
            "pressure": pressure_for(0.0),
            "method": "none",
            "row_structure": {"found": False},
            "patches": [],
            "confidence": 0.2,
            "note": "Almost no vegetation in this frame — bare soil, or the "
                    "camera was not looking at the crop.",
            "likely_weeds": [],
            "_overlay": None,
        }

    rows = find_rows(veg_mask)
    weed_mask = None
    method = "none"
    confidence = 0.3
    note = ""

    if rows["found"]:
        bands = _row_band_mask(veg_mask, rows["angle_deg"], rows.get("row_spacing_px"))
        if bands is not None:
            weed_mask = cv2.bitwise_and(veg_mask, cv2.bitwise_not(bands))
            method = "inter-row"
            # Strong, clean row structure is a genuinely reliable separator;
            # weak structure less so, so the confidence tracks it.
            confidence = round(min(0.9, 0.5 + rows["strength"]), 2)
            note = (
                "Weeds identified as vegetation growing between the crop rows. "
                "Weeds inside the row cannot be separated this way, so the true "
                "figure is at or above this one."
            )

    if weed_mask is None:
        weed_mask = _appearance_split(image, veg_mask)
        if weed_mask is not None:
            method = "appearance"
            confidence = 0.45
            note = (
                "No crop rows were visible, so weeds were separated by colour "
                "and leaf texture instead. Treat this as an indication, not a "
                "measurement — confirm on the ground before spraying."
            )

    if weed_mask is None:
        return {
            "status": "ok",
            "vegetation_coverage": round(veg_coverage, 4),
            "weed_coverage": 0.0,
            "pressure": pressure_for(0.0),
            "method": "inconclusive",
            "row_structure": rows,
            "patches": [],
            "confidence": 0.25,
            "note": "The canopy is uniform: no row structure, and no colour or "
                    "texture group that stands apart from the crop. Either the "
                    "field is clean or the weeds look exactly like the crop.",
            "likely_weeds": [w["id"] for w in likely_weeds(crop)],
            "_overlay": None,
        }

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    weed_mask = cv2.morphologyEx(weed_mask, cv2.MORPH_OPEN, kernel, iterations=1)
    weed_mask, patches = _significant_patches(weed_mask, frame_area)

    weed_px = int(np.count_nonzero(weed_mask))
    weed_coverage = weed_px / float(frame_area)
    weed_share_of_vegetation = weed_px / float(max(1, np.count_nonzero(veg_mask)))

    suspects = likely_weeds(crop)
    return {
        "status": "ok",
        "vegetation_coverage": round(veg_coverage, 4),
        "weed_coverage": round(weed_coverage, 4),
        "weed_share_of_vegetation": round(weed_share_of_vegetation, 4),
        "pressure": pressure_for(weed_coverage),
        "method": method,
        "row_structure": rows,
        "patches": patches,
        "confidence": confidence,
        "note": note,
        "likely_weeds": [
            {
                "id": weed["id"],
                "name": weed["name"],
                "local_name": weed["local_name"],
                "type": weed["type"],
                "identify": weed["identify"],
                "control": weed["control"],
            }
            for weed in suspects
        ],
        "_overlay": render_overlay(image, veg_mask, weed_mask),
        "_weed_mask": weed_mask,
        "_vegetation_mask": veg_mask,
    }
