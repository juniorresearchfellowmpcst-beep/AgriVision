"""Management-zone mapping via K-means clustering of a vegetation index.

Splits a field into **low / medium / high** vigor zones so an agronomist can
target scouting, fertiliser, or irrigation. Uses K-means (default k=3) over the
per-pixel index values.

A subtlety that matters: K-means assigns cluster ids arbitrarily, so raw labels
don't mean "low/medium/high". We reorder clusters by their mean index value, so
zone 0 is always the lowest-vigor group and zone k-1 the highest.
"""

import os
from typing import Dict, List, Optional

import cv2
import numpy as np


# Zone display colors (BGR): low=red, medium=amber, high=green. Extended below
# if more than three zones are requested.
_ZONE_COLORS = [
    (60, 60, 220),    # low  - red
    (60, 200, 240),   # med  - amber
    (80, 200, 80),    # high - green
]
_ZONE_LABELS_3 = ["low", "medium", "high"]


def _zone_labels(k: int) -> List[str]:
    if k == 3:
        return list(_ZONE_LABELS_3)
    if k == 2:
        return ["low", "high"]
    return [f"zone_{i}" for i in range(k)]


def _zone_color(i: int, k: int) -> tuple:
    if i < len(_ZONE_COLORS):
        return _ZONE_COLORS[i]
    # Interpolate red->green for arbitrary k.
    t = i / max(1, k - 1)
    return (int(80 * t), int(60 + 140 * t), int(220 * (1 - t)))


def kmeans_zones(
    index_map: np.ndarray,
    k: int = 3,
    valid_mask: Optional[np.ndarray] = None,
    seed: int = 42,
) -> Dict:
    """Cluster an index map into k vigor zones, ordered low→high.

    Args:
        index_map: 2-D float index (e.g. NDVI).
        k:         number of zones (3 = low/medium/high).
        valid_mask: optional bool mask of pixels to include; pixels that are 0
                    (no-data) are excluded automatically.
        seed:      RNG seed for reproducible clustering.

    Returns a dict with the labeled zone map (uint8, 255 = no-data), per-zone
    centers/labels/pixel-counts/area-fractions, and the cluster order applied.
    """
    if index_map.ndim != 2:
        raise ValueError("index_map must be 2-D")
    if k < 2:
        raise ValueError("k must be >= 2")

    h, w = index_map.shape
    finite = np.isfinite(index_map)
    mask = finite & (index_map != 0)
    if valid_mask is not None:
        mask &= valid_mask.astype(bool)

    samples = index_map[mask].astype(np.float32).reshape(-1, 1)
    if samples.shape[0] < k:
        raise ValueError(
            f"Only {samples.shape[0]} valid pixels for k={k}; need at least k."
        )

    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.2)
    cv2.setRNGSeed(seed)
    _compactness, labels, centers = cv2.kmeans(
        samples, k, None, criteria, 5, cv2.KMEANS_PP_CENTERS
    )
    labels = labels.ravel()
    centers = centers.ravel()

    # Reorder clusters by center value so 0 = lowest vigor ... k-1 = highest.
    order = np.argsort(centers)                 # old cluster ids, low→high
    remap = np.zeros(k, dtype=np.int32)
    remap[order] = np.arange(k)                 # old id -> ordered id
    ordered_labels = remap[labels]

    # Paint the zone map; 255 marks no-data so it's distinct from zone 0.
    zone_map = np.full((h, w), 255, dtype=np.uint8)
    zone_map[mask] = ordered_labels.astype(np.uint8)

    names = _zone_labels(k)
    total = int(ordered_labels.size)
    zones = []
    for z in range(k):
        count = int(np.count_nonzero(ordered_labels == z))
        zones.append({
            "zone": z,
            "label": names[z],
            "center_index": round(float(centers[order[z]]), 4),
            "pixels": count,
            "area_fraction": round(count / total, 4) if total else 0.0,
        })

    return {
        "k": k,
        "zone_map": zone_map,
        "zones": zones,
        "valid_pixels": total,
    }


def colorize_zones(zone_map: np.ndarray, k: int) -> np.ndarray:
    """Render the zone label map as a BGR image (no-data -> dark grey)."""
    h, w = zone_map.shape
    out = np.full((h, w, 3), 40, dtype=np.uint8)
    for z in range(k):
        out[zone_map == z] = _zone_color(z, k)
    return out


def zone_index_map(
    index_map: np.ndarray,
    k: int = 3,
    output_dir: Optional[str] = None,
    name: str = "ndvi",
    valid_mask: Optional[np.ndarray] = None,
) -> Dict:
    """Cluster an index map into zones and optionally write map + preview.

    Returns the kmeans_zones result plus output paths; the raw `zone_map` array
    is kept under `_zone_map` for chaining and dropped before JSON output.
    """
    result = kmeans_zones(index_map, k=k, valid_mask=valid_mask)
    zone_map = result.pop("zone_map")
    result["_zone_map"] = zone_map

    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        map_path = os.path.join(output_dir, f"{name}_zones.png")
        cv2.imwrite(map_path, zone_map)  # raw labels (0..k-1, 255=no-data)
        preview_path = os.path.join(output_dir, f"{name}_zones_preview.png")
        cv2.imwrite(preview_path, colorize_zones(zone_map, k))
        result["zone_map_file"] = map_path
        result["preview"] = preview_path

    return result
