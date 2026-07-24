"""Image utilities for leaf-disease screening.

Turns a raw uploaded photo into a small dictionary of *visual features* that the
heuristic classifier in :mod:`app.ai.disease_detector` reasons over:

    * how much of the frame is leaf (vs background),
    * of that leaf, the fraction that is healthy green, yellow (chlorotic),
      brown/dark (necrotic), or white/grey (mildew-like),
    * how the dead tissue is distributed — many small spots vs a few large
      blotches — which separates "leaf spot" from "blight".

Everything is plain OpenCV/NumPy so it runs offline with the packages already in
requirements.txt (no model download needed).
"""

from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

import cv2
import numpy as np

# Longest edge we downscale to before analysis. Big enough to keep spot detail,
# small enough that a phone photo processes in well under a second.
_MAX_EDGE = 720


def decode_image(data: bytes) -> Optional[np.ndarray]:
    """Decode raw image bytes into a BGR uint8 array, or ``None`` if invalid."""
    if not data:
        return None
    buf = np.frombuffer(data, dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    return img


def _resize(img: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    longest = max(h, w)
    if longest <= _MAX_EDGE:
        return img
    scale = _MAX_EDGE / float(longest)
    return cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)


def _fill_holes(mask: np.ndarray) -> np.ndarray:
    """Fill interior holes of a binary mask (regions enclosed by the shape).

    Used so a white powdery-mildew patch *inside* the leaf becomes part of the
    leaf silhouette, while the white background *outside* the leaf stays out.
    """
    h, w = mask.shape
    flood = mask.copy()
    ff_mask = np.zeros((h + 2, w + 2), np.uint8)
    # Flood the exterior background starting from a corner; whatever the flood
    # can't reach is an enclosed hole.
    cv2.floodFill(flood, ff_mask, (0, 0), 255)
    holes = cv2.bitwise_not(flood)
    return cv2.bitwise_or(mask, holes)


def _leaf_mask(hsv: np.ndarray) -> np.ndarray:
    """Best-effort mask of the plant/leaf region, excluding background.

    Combines "anything vegetation-coloured or diseased-leaf-coloured" (greens,
    yellows, browns, dark necrosis) with any bright white/grey pixels that fall
    *inside* the leaf silhouette — that last part is what lets powdery-mildew
    coating be measured instead of being mistaken for background.
    """
    h, s, v = cv2.split(hsv)

    # Vegetation + diseased tissue hues: green, yellow, and brown/orange.
    # Hue is 0-179 in OpenCV. Keep reasonably saturated, non-black pixels.
    colourful = (s > 40) & (v > 30)
    green_yellow_brown = (h <= 95)  # 0..95 covers red/brown/orange/yellow/green
    veg = colourful & green_yellow_brown

    # Also include dark necrotic/very-dark leaf tissue (low saturation, dark).
    dark_tissue = (v < 90) & (s > 20)

    veg_mask = (veg | dark_tissue).astype(np.uint8) * 255

    # Clean up speckle and close small gaps in the coloured tissue.
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    veg_mask = cv2.morphologyEx(veg_mask, cv2.MORPH_OPEN, kernel, iterations=1)

    # Approximate the whole leaf silhouette: bridge across white coating gaps
    # with a larger close, then fill enclosed holes.
    big_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    silhouette = cv2.morphologyEx(veg_mask, cv2.MORPH_CLOSE, big_kernel, iterations=2)
    silhouette = _fill_holes(silhouette)
    # Erode back the halo the large close added so we don't grab background.
    silhouette = cv2.erode(silhouette, big_kernel, iterations=1)

    # Bright, desaturated pixels (powdery coating) that sit inside the leaf.
    bright_white = ((s < 45) & (v >= 170)).astype(np.uint8) * 255
    white_on_leaf = cv2.bitwise_and(bright_white, silhouette)

    mask = cv2.bitwise_or(veg_mask, white_on_leaf)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    return mask


def _spot_stats(necrotic_mask: np.ndarray, leaf_area: int) -> Tuple[int, float]:
    """Count discrete necrotic blobs and the largest blob's share of the leaf.

    Many small blobs => leaf-spot pattern; one/few large blobs => blight.
    Returns (spot_count, largest_blob_fraction_of_leaf).
    """
    if leaf_area <= 0:
        return 0, 0.0
    num, _labels, stats, _cent = cv2.connectedComponentsWithStats(
        (necrotic_mask > 0).astype(np.uint8), connectivity=8
    )
    # Ignore the background label (0) and trivially small noise blobs.
    min_area = max(12, int(leaf_area * 0.0008))
    areas = [stats[i, cv2.CC_STAT_AREA] for i in range(1, num) if stats[i, cv2.CC_STAT_AREA] >= min_area]
    if not areas:
        return 0, 0.0
    largest = max(areas)
    return len(areas), largest / float(leaf_area)


def extract_features(img_bgr: np.ndarray) -> Dict[str, Any]:
    """Extract the colour/lesion feature summary used for classification.

    All ``*_fraction`` values are shares of the detected **leaf** area (0..1),
    so they are comparable regardless of how much background is in the frame.
    """
    img = _resize(img_bgr)
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)

    leaf = _leaf_mask(hsv)
    leaf_bool = leaf > 0
    leaf_area = int(leaf_bool.sum())
    total = img.shape[0] * img.shape[1]

    # If we could barely find any leaf, report low coverage so the caller can
    # ask for a better photo instead of guessing.
    coverage = leaf_area / float(total) if total else 0.0
    if leaf_area < max(500, total * 0.02):
        return {
            "leaf_coverage": round(coverage, 4),
            "leaf_found": False,
            "green_fraction": 0.0,
            "yellow_fraction": 0.0,
            "brown_fraction": 0.0,
            "white_fraction": 0.0,
            "affected_fraction": 0.0,
            "spot_count": 0,
            "largest_lesion_fraction": 0.0,
        }

    # Per-pixel colour classes, evaluated only within the leaf mask.
    healthy_green = leaf_bool & (h >= 35) & (h <= 90) & (s >= 45) & (v >= 40)

    yellow = leaf_bool & (h >= 20) & (h < 35) & (s >= 45) & (v >= 60)

    # White / grey powdery coating: very low saturation but bright.
    white = leaf_bool & (s < 45) & (v >= 170)

    # Brown / dark necrotic tissue: warm low hue OR simply dark, and not already
    # counted as bright green/yellow/white.
    warm_brown = (h <= 20) | (h >= 160)
    dark = v < 110
    brown = leaf_bool & (warm_brown | dark) & ~healthy_green & ~white & ~yellow

    green_area = int(healthy_green.sum())
    yellow_area = int(yellow.sum())
    white_area = int(white.sum())
    brown_area = int(brown.sum())

    green_fraction = green_area / leaf_area
    yellow_fraction = yellow_area / leaf_area
    white_fraction = white_area / leaf_area
    brown_fraction = brown_area / leaf_area

    # "Affected" = leaf tissue that is not healthy green.
    affected_fraction = max(0.0, 1.0 - green_fraction)

    # Distribution of necrotic tissue -> spot vs blight signal.
    necrotic_mask = (brown | yellow).astype(np.uint8) * 255
    necrotic_mask = cv2.bitwise_and(necrotic_mask, leaf)
    spot_count, largest_lesion_fraction = _spot_stats(necrotic_mask, leaf_area)

    return {
        "leaf_coverage": round(coverage, 4),
        "leaf_found": True,
        "green_fraction": round(green_fraction, 4),
        "yellow_fraction": round(yellow_fraction, 4),
        "brown_fraction": round(brown_fraction, 4),
        "white_fraction": round(white_fraction, 4),
        "affected_fraction": round(affected_fraction, 4),
        "spot_count": int(spot_count),
        "largest_lesion_fraction": round(largest_lesion_fraction, 4),
    }
