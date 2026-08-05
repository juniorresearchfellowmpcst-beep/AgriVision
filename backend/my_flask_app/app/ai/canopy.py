"""Colour and lesion features for a *canopy* frame (not a single leaf).

:mod:`app.ai.utils` extracts features from a photo of one leaf held against a
plain background. A frame from a drone on a low, slow pass is a different
picture: soil between the plants, several plants at once, and no clean
silhouette. Reusing the leaf extractor on it goes wrong in a specific way —
bare soil is brown, so "necrotic tissue" comes back at 60% on a perfectly
healthy field.

So the plant mask is built the other way round here:

    1. find unambiguously green pixels (Excess Green) — that is definitely crop
    2. close and hole-fill them into a canopy silhouette
    3. add discoloured pixels that fall *inside* that silhouette

Step 3 is what lets a yellow rust stripe or a brown blight blotch be measured
as diseased crop, while the same colours out on the soil between rows are
ignored. It is the same trick the leaf extractor uses to keep white powdery
mildew from being read as background, applied to a whole canopy.

The output feeds :mod:`app.ai.field_scan`, which matches it against the
colour/pattern signatures in :mod:`app.ai.crop_kb`.
"""

from __future__ import annotations

from typing import Any, Dict

import cv2
import numpy as np

from .weed_detector import excess_green

_MAX_EDGE = 720


def _resize(img: np.ndarray) -> np.ndarray:
    height, width = img.shape[:2]
    longest = max(height, width)
    if longest <= _MAX_EDGE:
        return img
    scale = _MAX_EDGE / float(longest)
    return cv2.resize(
        img, (max(1, int(width * scale)), max(1, int(height * scale))),
        interpolation=cv2.INTER_AREA,
    )


def _fill_holes(mask: np.ndarray) -> np.ndarray:
    """Fill regions fully enclosed by the mask (gaps inside the canopy).

    The one-pixel border matters. Flooding the unpadded mask from a corner
    cannot get *past* a shape that spans the frame, so the bare soil between
    two full-height crop rows counts as an enclosed hole and the whole
    inter-row is absorbed into the canopy. Padding first gives the flood a way
    around the outside, so only genuinely enclosed regions — a lesion inside a
    leaf — are filled.
    """
    padded = cv2.copyMakeBorder(mask, 1, 1, 1, 1, cv2.BORDER_CONSTANT, value=0)
    flood = padded.copy()
    scratch = np.zeros((padded.shape[0] + 2, padded.shape[1] + 2), np.uint8)
    cv2.floodFill(flood, scratch, (0, 0), 255)
    holes = cv2.bitwise_not(flood)[1:-1, 1:-1]
    return cv2.bitwise_or(mask, holes)


def canopy_mask(img_bgr: np.ndarray) -> Dict[str, np.ndarray]:
    """Split the frame into crop canopy, and the discoloured part of it."""
    exg = excess_green(img_bgr)
    green = ((exg > 0.05) * 255).astype(np.uint8)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    green = cv2.morphologyEx(green, cv2.MORPH_OPEN, kernel, iterations=1)

    # Bridge leaf-scale gaps only, then take whatever the green now *encloses*.
    #
    # The closing has to stay small. Widen it enough to bridge a crop row's
    # inter-row gap and the bare soil between the rows becomes "enclosed", and
    # a healthy row crop reads as 60% necrotic — because MP's soil is exactly
    # the reddish-brown that necrosis is. Hole filling is the safe operator
    # here: a lesion inside a leaf is enclosed by green, while inter-row soil
    # runs to the edge of the frame and is not.
    small = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    silhouette = cv2.morphologyEx(green, cv2.MORPH_CLOSE, small, iterations=1)
    silhouette = _fill_holes(silhouette)

    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    hue, saturation, value = cv2.split(hsv)

    # Discoloured-but-still-plant: warm hues or bright desaturated patches.
    warm = ((hue <= 35) & (saturation >= 50) & (value >= 45))
    pale = ((saturation < 55) & (value >= 165))
    discoloured = ((warm | pale) * 255).astype(np.uint8)
    discoloured = cv2.bitwise_and(discoloured, silhouette)

    plant = cv2.bitwise_or(green, discoloured)
    plant = cv2.morphologyEx(plant, cv2.MORPH_CLOSE, kernel, iterations=1)

    return {"plant": plant, "green": green, "discoloured": discoloured, "hsv": hsv}


def _lesion_shape(mask: np.ndarray, plant_area: int) -> Dict[str, float]:
    """Count discrete lesions and describe their shape.

    Three numbers separate the patterns the knowledge base talks about: many
    small blobs is *spots*, one big blob is *blotch*, and long thin blobs are
    *streaks* — which is exactly how yellow rust differs from brown rust in a
    photograph.
    """
    count, _labels, stats, _centroids = cv2.connectedComponentsWithStats(
        (mask > 0).astype(np.uint8), connectivity=8
    )
    minimum = max(15, int(plant_area * 0.0005))

    areas, elongations = [], []
    for i in range(1, count):
        area = int(stats[i, cv2.CC_STAT_AREA])
        if area < minimum:
            continue
        areas.append(area)
        width = max(1, int(stats[i, cv2.CC_STAT_WIDTH]))
        height = max(1, int(stats[i, cv2.CC_STAT_HEIGHT]))
        elongations.append(max(width, height) / float(min(width, height)))

    if not areas:
        return {"spot_count": 0, "largest_lesion_fraction": 0.0, "elongation": 1.0}

    return {
        "spot_count": float(len(areas)),
        "largest_lesion_fraction": max(areas) / float(plant_area or 1),
        "elongation": float(np.median(elongations)),
    }


def extract_canopy_features(img_bgr: np.ndarray) -> Dict[str, Any]:
    """Colour fractions and lesion shape for a canopy frame.

    All ``*_fraction`` values are shares of the detected **plant** area, so a
    frame that is 30% soil and one that is 70% soil are comparable.
    """
    image = _resize(img_bgr if img_bgr.ndim == 3 else cv2.cvtColor(img_bgr, cv2.COLOR_GRAY2BGR))
    masks = canopy_mask(image)
    plant = masks["plant"]
    hue, saturation, value = cv2.split(masks["hsv"])

    plant_bool = plant > 0
    plant_area = int(plant_bool.sum())
    total = image.shape[0] * image.shape[1]
    coverage = plant_area / float(total or 1)

    if plant_area < max(400, total * 0.02):
        return {
            "canopy_coverage": round(coverage, 4),
            "canopy_found": False,
            "green_fraction": 0.0, "yellow_fraction": 0.0, "orange_fraction": 0.0,
            "brown_fraction": 0.0, "white_fraction": 0.0, "grey_fraction": 0.0,
            "affected_fraction": 0.0, "spot_count": 0,
            "largest_lesion_fraction": 0.0, "elongation": 1.0, "mosaic_score": 0.0,
        }

    # Hue bands (OpenCV hue is 0-179).
    healthy = plant_bool & (hue >= 35) & (hue <= 90) & (saturation >= 45) & (value >= 40)
    yellow = plant_bool & (hue >= 22) & (hue < 35) & (saturation >= 60) & (value >= 70)
    orange = plant_bool & (hue >= 8) & (hue < 22) & (saturation >= 70) & (value >= 60)
    white = plant_bool & (saturation < 55) & (value >= 165)
    grey = plant_bool & (saturation < 55) & (value >= 70) & (value < 165)
    brown = (
        plant_bool
        & (((hue < 22) & (saturation >= 40)) | (value < 80))
        & ~healthy & ~yellow & ~orange & ~white
    )

    def share(mask) -> float:
        return float(int(mask.sum())) / plant_area

    green_fraction = share(healthy)
    shape = _lesion_shape(
        cv2.bitwise_and(
            ((yellow | orange | brown) * 255).astype(np.uint8), plant
        ),
        plant_area,
    )

    # Mosaic: healthy green and chlorotic yellow interleaved at a fine scale,
    # which is what a viral mosaic looks like and what a nutrient-starved
    # uniformly-pale canopy does not.
    hue_on_plant = hue.astype(np.float32)
    blurred = cv2.blur(hue_on_plant, (9, 9))
    local_variation = np.abs(hue_on_plant - blurred)
    mosaic_score = float(local_variation[plant_bool].mean() / 20.0)

    return {
        "canopy_coverage": round(coverage, 4),
        "canopy_found": True,
        "green_fraction": round(green_fraction, 4),
        "yellow_fraction": round(share(yellow), 4),
        "orange_fraction": round(share(orange), 4),
        "brown_fraction": round(share(brown), 4),
        "white_fraction": round(share(white), 4),
        "grey_fraction": round(share(grey), 4),
        "affected_fraction": round(max(0.0, 1.0 - green_fraction), 4),
        "spot_count": int(shape["spot_count"]),
        "largest_lesion_fraction": round(shape["largest_lesion_fraction"], 4),
        "elongation": round(shape["elongation"], 2),
        "mosaic_score": round(min(mosaic_score, 2.0), 3),
    }
