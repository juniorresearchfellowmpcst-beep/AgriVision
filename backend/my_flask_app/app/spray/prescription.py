"""K-means spray prescription from a multispectral capture.

This is the module that turns "the drone photographed the block" into "spray
these 4 patches and skip the other 83% of the field".

    band frames ─► reflectance ─► vegetation index ─► K-MEANS (k=3)
                ─► severe / moderate / healthy classes
                ─► clean up + find sprayable patches
                ─► cost the options, so the operator can choose

Why K-means rather than a fixed NDVI threshold: a threshold that is right for
irrigated wheat in Vidisha in January is wrong for rainfed soybean in
Chhindwara in August. Clustering asks a different question — "which parts of
*this* field are worst relative to the rest of it" — which is the question a
variable-rate spray actually needs answered. The trade-off is that a uniformly
healthy field still produces a "worst" cluster, so the module reports the
spread between cluster means and flags a prescription as low-contrast when
there is no real difference to act on.

The pesticide saving is the whole point of the feature: a blanket spray treats
100% of the block, and this treats the affected fraction — at a reduced rate on
the moderate class, because moderate damage does not need the severe dose.
"""

from __future__ import annotations

import os
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np

from app.preprocessing.alignment import align_stack
from app.preprocessing.config import PipelineConfig
from app.preprocessing.indices import INDEX_REGISTRY, available_indices, compute_index
from app.preprocessing.io import read_band_stack
from app.preprocessing.reflectance import (
    apply_reflectance,
    compute_scale_factors,
    pseudo_reflectance,
)
from app.preprocessing.zoning import kmeans_zones

from .geo import Georeferencer

# Severity classes, worst first. These are the spray decision, not a diagnosis:
# "severe" means "this part of the canopy is the worst in the field", which is
# what a targeted spray is aimed at.
SEVERITY_ORDER = ("severe", "moderate", "healthy")

# Display colours (BGR) for the prescription map.
_SEVERITY_COLORS = {
    "severe": (60, 60, 220),      # red
    "moderate": (60, 200, 240),   # amber
    "healthy": (90, 190, 90),     # green
}

# Preference order for the index the clustering runs on — first computable wins.
_INDEX_PREFERENCE = ["ndvi", "osavi", "savi", "ndre", "evi2", "gndvi", "vari"]

# Litres of spray mix per hectare. UAV spraying runs far leaner than a tractor
# boom; 20 L/ha is a common Indian drone-spray rate for a full-cover pass.
DEFAULT_DOSE_L_PER_HA = 20.0

# Moderate zones get a reduced rate. This is where a *variable*-rate spray
# saves chemical beyond simply skipping the healthy ground.
DEFAULT_MODERATE_RATE = 0.6

# Ignore specks smaller than this on the ground — a boom cannot target them and
# a "patch" of five pixels is usually noise, not disease.
DEFAULT_MIN_PATCH_M2 = 4.0

# Below this spread between the worst and best cluster means, the field is
# effectively uniform and a targeted prescription is not meaningful.
_LOW_CONTRAST_SPREAD = 0.08


class PrescriptionError(ValueError):
    """Something about the capture makes a prescription impossible."""


def _severity_ramp(k: int, higher_is_healthier: bool) -> List[str]:
    """Severity for each index-ordered cluster (0 = lowest index value)."""
    if k == 3:
        ramp = ["severe", "moderate", "healthy"]
    elif k == 2:
        ramp = ["severe", "healthy"]
    else:
        ramp = []
        for i in range(k):
            frac = i / max(1, k - 1)
            ramp.append(
                "severe" if frac < 1 / 3 else "moderate" if frac < 2 / 3 else "healthy"
            )
    # For a stress index (PSRI, NDWI) a HIGH value is the bad news, so the
    # ramp runs the other way. Getting this wrong prescribes spray onto the
    # healthiest ground in the field.
    return ramp if higher_is_healthier else list(reversed(ramp))


def _pick_index(band_names: List[str], requested: Optional[str]) -> str:
    usable = available_indices(band_names)
    if requested and requested.lower() in usable:
        return requested.lower()
    for key in _INDEX_PREFERENCE:
        if key in usable:
            return key
    if usable:
        return usable[0]
    raise PrescriptionError(
        "None of the vegetation indices can be computed from the captured "
        f"bands ({', '.join(band_names) or 'none'}). A red + NIR pair is the "
        "minimum for a spray prescription."
    )


def _reflectance_stack(
    band_paths: Dict[str, str],
    panel_paths: Optional[Dict[str, str]],
    config: PipelineConfig,
):
    """Bands on disk → aligned reflectance stack (calibrated when possible)."""
    band_order = [b for b in config.bands if b in band_paths] or list(band_paths)
    if not band_order:
        raise PrescriptionError("No band images in this capture.")

    scene = read_band_stack({b: band_paths[b] for b in band_order}, band_order)

    calibrated = False
    if panel_paths and all(b in panel_paths for b in band_order):
        panel = read_band_stack({b: panel_paths[b] for b in band_order}, band_order)
        stack = apply_reflectance(scene, compute_scale_factors(panel, config), config)
        calibrated = True
    else:
        # Uncalibrated path. pseudo_reflectance deliberately uses ONE shared
        # scale across bands — per-band stretching would flatten the NIR/Red
        # gap and take NDVI (and this whole prescription) to zero.
        stack = pseudo_reflectance(scene)

    if len(band_order) > 1:
        stack, _report = align_stack(stack, config.alignment)

    return stack, calibrated


def _clean_mask(mask: np.ndarray, min_patch_px: int) -> np.ndarray:
    """Turn a per-pixel class mask into something a spray boom can follow.

    Raw K-means output is salt-and-pepper at the class boundaries. Opening
    drops the pepper, closing joins a patch that clustering split in two, and
    the caller then discards whatever is still smaller than the boom can aim
    at. Without this the "prescription" is thousands of one-pixel targets.
    """
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    cleaned = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    cleaned = cv2.morphologyEx(cleaned, cv2.MORPH_CLOSE, kernel, iterations=2)
    return cleaned


def _patches(
    mask: np.ndarray,
    severity: str,
    min_patch_px: int,
    georeferencer: Georeferencer,
    start_index: int,
) -> List[Dict]:
    """Connected components of a class mask, as sprayable targets."""
    count, _labels, stats, centroids = cv2.connectedComponentsWithStats(
        (mask > 0).astype(np.uint8), connectivity=8
    )

    area_per_px = georeferencer.area_m2_per_pixel()
    patches: List[Dict] = []
    for i in range(1, count):  # 0 is the background label
        area_px = int(stats[i, cv2.CC_STAT_AREA])
        if area_px < min_patch_px:
            continue

        cx, cy = float(centroids[i][0]), float(centroids[i][1])
        x, y = int(stats[i, cv2.CC_STAT_LEFT]), int(stats[i, cv2.CC_STAT_TOP])
        w, h = int(stats[i, cv2.CC_STAT_WIDTH]), int(stats[i, cv2.CC_STAT_HEIGHT])

        patch = {
            "id": start_index + len(patches),
            "severity": severity,
            "pixels": area_px,
            "centroid_px": [round(cx, 1), round(cy, 1)],
            "bbox_px": [x, y, w, h],
            "area_m2": round(area_px * area_per_px, 2) if area_per_px else None,
            "area_ha": round(area_px * area_per_px / 10_000.0, 5) if area_per_px else None,
        }

        position = georeferencer.to_latlon(cx, cy)
        if position:
            patch["lat"], patch["lon"] = round(position[0], 7), round(position[1], 7)
            # Radius of a circle with the same area — how wide the boom pass
            # over this patch needs to be.
            if area_per_px:
                patch["radius_m"] = round(
                    float(np.sqrt(area_px * area_per_px / np.pi)), 2
                )
        patches.append(patch)

    # Biggest first: if the tank runs out, it should run out on the small ones.
    patches.sort(key=lambda p: p["pixels"], reverse=True)
    for offset, patch in enumerate(patches):
        patch["id"] = start_index + offset
    return patches


def _render_map(
    zone_map: np.ndarray,
    cluster_severity: Dict[int, str],
    patches: List[Dict],
    path: str,
) -> str:
    """Stoplight prescription image with the sprayable patches outlined."""
    height, width = zone_map.shape
    canvas = np.full((height, width, 3), 45, dtype=np.uint8)  # no-data = grey
    for cluster, severity in cluster_severity.items():
        canvas[zone_map == cluster] = _SEVERITY_COLORS[severity]

    for patch in patches:
        x, y, w, h = patch["bbox_px"]
        cv2.rectangle(canvas, (x, y), (x + w, y + h), (255, 255, 255), 1)
        cv2.putText(
            canvas, str(patch["id"]), (x + 2, max(10, y + 12)),
            cv2.FONT_HERSHEY_SIMPLEX, 0.35, (255, 255, 255), 1, cv2.LINE_AA,
        )

    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    cv2.imwrite(path, canvas)
    return path


def _options(
    areas_ha: Dict[str, Optional[float]],
    fractions: Dict[str, float],
    field_ha: Optional[float],
    dose_l_per_ha: float,
    moderate_rate: float,
) -> List[Dict]:
    """Cost each spray choice against a blanket pass over the same block.

    Percentages always work (they come from area fractions); litres only
    appear when we know how big the block is on the ground.
    """
    severe_f = fractions.get("severe", 0.0)
    moderate_f = fractions.get("moderate", 0.0)

    def build(key: str, label: str, detail: str, levels: Tuple[str, ...]) -> Dict:
        # Chemical is proportional to area *and* rate: the moderate class is
        # sprayed at a reduced rate, so it costs less than its area suggests.
        weighted = 0.0
        treated_fraction = 0.0
        for level in levels:
            rate = 1.0 if level == "severe" else moderate_rate
            weighted += fractions.get(level, 0.0) * rate
            treated_fraction += fractions.get(level, 0.0)

        option = {
            "id": key,
            "label": label,
            "detail": detail,
            "levels": list(levels),
            "treated_fraction": round(treated_fraction, 4),
            "treated_percent": int(round(treated_fraction * 100)),
            "chemical_fraction": round(weighted, 4),
            "saving_percent": int(round((1.0 - weighted) * 100)),
            "rates_l_per_ha": {
                "severe": round(dose_l_per_ha, 2),
                "moderate": round(dose_l_per_ha * moderate_rate, 2),
            },
        }

        if field_ha:
            treated_ha = sum(areas_ha.get(level) or 0.0 for level in levels)
            blanket_l = field_ha * dose_l_per_ha
            spray_l = sum(
                (areas_ha.get(level) or 0.0)
                * dose_l_per_ha
                * (1.0 if level == "severe" else moderate_rate)
                for level in levels
            )
            option.update({
                "treated_ha": round(treated_ha, 4),
                "chemical_l": round(spray_l, 2),
                "blanket_l": round(blanket_l, 2),
                "saved_l": round(max(0.0, blanket_l - spray_l), 2),
            })
        return option

    options = [
        build(
            "severe_only",
            "Spray severely affected only",
            "Treats the worst cluster and leaves the rest of the block alone. "
            "The largest saving, and the right call when the problem is a few "
            "defined patches.",
            ("severe",),
        ),
        build(
            "severe_moderate",
            "Spray severe + moderate",
            "Full rate on the worst zones and a reduced rate on the moderate "
            "ones. Choose this when the problem is spreading and the moderate "
            "zones are the front line.",
            ("severe", "moderate"),
        ),
        build(
            "blanket",
            "Spray the whole block",
            "No targeting — shown so the saving from the options above is "
            "something you can see rather than take on trust.",
            (),
        ),
    ]
    # The blanket row is the baseline: 100% treated, nothing saved.
    blanket = options[-1]
    blanket.update({
        "treated_fraction": 1.0,
        "treated_percent": 100,
        "chemical_fraction": 1.0,
        "saving_percent": 0,
        "levels": ["severe", "moderate", "healthy"],
    })
    if field_ha:
        blanket.update({
            "treated_ha": round(field_ha, 4),
            "chemical_l": round(field_ha * dose_l_per_ha, 2),
            "blanket_l": round(field_ha * dose_l_per_ha, 2),
            "saved_l": 0.0,
        })

    # Recommend, but don't decide — the operator confirms either way.
    combined = severe_f + moderate_f
    if combined >= 0.85:
        recommended = "blanket"
    elif moderate_f >= 0.10:
        recommended = "severe_moderate"
    else:
        recommended = "severe_only"
    for option in options:
        option["recommended"] = option["id"] == recommended

    return options


def prescribe(
    band_paths: Dict[str, str],
    output_dir: str,
    k: int = 3,
    index: Optional[str] = None,
    panel_paths: Optional[Dict[str, str]] = None,
    config: Optional[PipelineConfig] = None,
    lat: Optional[float] = None,
    lon: Optional[float] = None,
    alt_m: Optional[float] = None,
    heading_deg: Optional[float] = None,
    fov_deg: Optional[float] = None,
    field_area_ha: Optional[float] = None,
    dose_l_per_ha: float = DEFAULT_DOSE_L_PER_HA,
    moderate_rate: float = DEFAULT_MODERATE_RATE,
    min_patch_m2: float = DEFAULT_MIN_PATCH_M2,
    save_outputs: bool = True,
) -> Dict:
    """Build a spray prescription from one multispectral capture.

    Returns a JSON-safe dict: the clusters and what they mean, the sprayable
    patches (with coordinates when the capture is georeferenced), the costed
    spray options, and the rendered prescription map.
    """
    if k < 2:
        raise PrescriptionError("k must be at least 2 (affected vs healthy).")
    if k > 6:
        raise PrescriptionError("k above 6 splits the field past what a boom can follow.")

    config = config or PipelineConfig()
    stack, calibrated = _reflectance_stack(band_paths, panel_paths, config)

    index_key = _pick_index(stack.band_names, index)
    spec = INDEX_REGISTRY[index_key]
    index_map = compute_index(stack, index_key)

    # ── K-means: the clustering the whole feature rests on ────────────────
    try:
        clustered = kmeans_zones(index_map, k=k)
    except ValueError as exc:
        raise PrescriptionError(
            f"Could not cluster this capture: {exc}. The frame may be blank or "
            "almost entirely no-data."
        ) from exc

    zone_map = clustered["zone_map"]           # uint8 labels, 255 = no-data
    clusters = clustered["zones"]              # ordered by mean index, ascending
    ramp = _severity_ramp(k, spec.higher_is_healthier)

    cluster_severity = {c["zone"]: ramp[c["zone"]] for c in clusters}
    fractions = {level: 0.0 for level in SEVERITY_ORDER}
    cluster_rows = []
    for cluster in clusters:
        severity = cluster_severity[cluster["zone"]]
        fractions[severity] += cluster["area_fraction"]
        cluster_rows.append({
            "cluster": cluster["zone"],
            "severity": severity,
            "mean_index": cluster["center_index"],
            "pixels": cluster["pixels"],
            "area_fraction": cluster["area_fraction"],
        })
    fractions = {level: round(value, 4) for level, value in fractions.items()}

    height, width = index_map.shape
    georeferencer = Georeferencer(
        image_size=(width, height),
        lat=lat, lon=lon, alt_m=alt_m, fov_deg=fov_deg, heading_deg=heading_deg,
    )

    # Field area: measured from the footprint when we can, otherwise whatever
    # the operator told us the block is.
    area_per_px = georeferencer.area_m2_per_pixel()
    valid_px = int(clustered["valid_pixels"])
    field_ha = (
        valid_px * area_per_px / 10_000.0 if area_per_px else field_area_ha
    )

    min_patch_px = (
        max(12, int(min_patch_m2 / area_per_px)) if area_per_px
        else max(25, int(valid_px * 0.002))
    )

    # ── sprayable patches per treatable class ─────────────────────────────
    patches: List[Dict] = []
    targeted_px = {level: 0 for level in SEVERITY_ORDER}
    for severity in ("severe", "moderate"):
        members = [c for c, s in cluster_severity.items() if s == severity]
        if not members:
            continue
        mask = np.isin(zone_map, members).astype(np.uint8) * 255
        mask = _clean_mask(mask, min_patch_px)
        found = _patches(mask, severity, min_patch_px, georeferencer, len(patches))
        patches.extend(found)
        targeted_px[severity] = sum(p["pixels"] for p in found)

    # Two different numbers, and the difference matters: the cluster fraction
    # is how much of the field K-means called affected; the targeted fraction
    # is how much of it survived cleanup into patches a boom can actually
    # cover. The plan and the saving are costed on the targeted figure.
    targeted_fractions = {
        level: round(targeted_px[level] / valid_px, 4) if valid_px else 0.0
        for level in SEVERITY_ORDER
    }
    areas_ha = {
        level: (targeted_px[level] * area_per_px / 10_000.0 if area_per_px else None)
        for level in SEVERITY_ORDER
    }

    options = _options(
        areas_ha=areas_ha,
        fractions=targeted_fractions,
        field_ha=field_ha,
        dose_l_per_ha=dose_l_per_ha,
        moderate_rate=moderate_rate,
    )

    means = [c["center_index"] for c in clusters]
    spread = round(float(max(means) - min(means)), 4) if means else 0.0
    low_contrast = spread < _LOW_CONTRAST_SPREAD

    outputs = {}
    if save_outputs:
        os.makedirs(output_dir, exist_ok=True)
        outputs["prescription_map"] = _render_map(
            zone_map, cluster_severity, patches,
            os.path.join(output_dir, "spray_prescription.png"),
        )
        from app.preprocessing.indices import colorize_index

        preview = os.path.join(output_dir, f"{index_key}_preview.png")
        cv2.imwrite(preview, colorize_index(index_map, spec))
        outputs["index_preview"] = preview

    notes = []
    if not calibrated:
        notes.append(
            "Uncalibrated capture — index values are relative, which is fine "
            "for ranking zones within this field but not for comparing fields."
        )
    if low_contrast:
        notes.append(
            f"The field is fairly uniform (index spread {spread}). K-means will "
            "still name a worst cluster, but there may be nothing real to "
            "target — ground-truth before spraying."
        )
    if not georeferencer.can_georeference:
        notes.append(
            "This capture cannot be turned into spray waypoints: "
            + "; ".join(georeferencer.describe()["missing"] or ["missing position data"])
            + "."
        )
    if not patches:
        notes.append(
            "No patch was large enough to target. Either the field is clean, "
            "or the affected pixels are scattered too thinly for a boom pass."
        )

    return {
        "status": "ok",
        "index": index_key,
        "index_name": spec.name,
        "higher_is_healthier": spec.higher_is_healthier,
        "calibrated": calibrated,
        "k": k,
        "clusters": cluster_rows,
        "cluster_spread": spread,
        "low_contrast": low_contrast,
        "severity_fractions": fractions,
        "targeted_fractions": targeted_fractions,
        "areas_ha": {
            level: round(value, 5) if value is not None else None
            for level, value in areas_ha.items()
        },
        "field_ha": round(field_ha, 4) if field_ha else None,
        "patches": patches,
        "patch_count": len(patches),
        "options": options,
        "coverage": georeferencer.describe(),
        "dose_l_per_ha": dose_l_per_ha,
        "moderate_rate": moderate_rate,
        "bands_used": stack.band_names,
        "outputs": outputs,
        "notes": notes,
    }


def patches_for_levels(prescription: Dict, levels: List[str]) -> List[Dict]:
    """The patches a chosen spray option would actually treat."""
    wanted = {str(level).lower() for level in levels or []}
    return [p for p in prescription.get("patches", []) if p.get("severity") in wanted]
