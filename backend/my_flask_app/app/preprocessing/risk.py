"""Crop-risk zoning, field report, and agronomic action plan.

Turns the vegetation indices into decision support:

  1. `risk_zones`  — cluster a health index into HIGH / MEDIUM / LOW **risk**
     regions (low vigor = high risk) and render a stoplight map.
  2. `generate_report`      — a structured field-health summary with flags.
  3. `generate_action_plan` — prioritised, index-driven recommendations.

The recommendations are heuristic agronomic decision-support, not a prescription
— every action tells the operator to ground-truth before acting. Thresholds are
deliberately conservative and documented inline so an agronomist can tune them.
"""

import os
from typing import Dict, List, Optional

import cv2
import numpy as np

from .indices import INDEX_REGISTRY
from .zoning import kmeans_zones


# Risk level → display color (BGR): high=red, medium=amber, low=green.
_RISK_COLORS = {"high": (60, 60, 220), "medium": (60, 200, 240), "low": (80, 200, 80)}
_RISK_ORDER = ["high", "medium", "low"]


def risk_zones(
    index_map: np.ndarray,
    higher_is_healthier: bool = True,
    k: int = 3,
    output_dir: Optional[str] = None,
    name: str = "risk",
) -> Dict:
    """Cluster a health index into high/medium/low risk regions.

    K-means groups pixels by index value; groups are then mapped to risk by
    vigor. For a "higher is healthier" index (NDVI, NDRE) the lowest-value
    cluster is the HIGHEST risk; for a stress index (PSRI, NDWI) it inverts.

    Returns per-zone risk level + area fraction + mean index, plus a colored
    risk-map file when `output_dir` is given.
    """
    result = kmeans_zones(index_map, k=k)      # zones ordered low→high index
    zone_map = result.pop("zone_map")          # uint8 labels 0..k-1, 255 no-data
    zones = result["zones"]                    # ordered by center_index asc

    # Map ordered clusters (0=lowest index ... k-1=highest) to risk levels.
    # Healthy-high index: lowest index = high risk. Stress index: reverse.
    risk_for_rank = _risk_ramp(k)
    if not higher_is_healthier:
        risk_for_rank = list(reversed(risk_for_rank))

    zone_risk = {}                              # cluster label -> risk level
    enriched = []
    for z in zones:
        level = risk_for_rank[z["zone"]]
        zone_risk[z["zone"]] = level
        enriched.append({
            "risk": level,
            "mean_index": z["center_index"],
            "area_fraction": z["area_fraction"],
            "pixels": z["pixels"],
        })

    # Aggregate area by risk level (clusters can share a level when k>3).
    distribution = {lvl: 0.0 for lvl in _RISK_ORDER}
    for z in enriched:
        distribution[z["risk"]] += z["area_fraction"]
    distribution = {lvl: round(frac, 4) for lvl, frac in distribution.items()}

    out = {
        "k": k,
        "higher_is_healthier": higher_is_healthier,
        "zones": sorted(enriched, key=lambda z: _RISK_ORDER.index(z["risk"])),
        "distribution": distribution,
        "_zone_map": zone_map,
        "_zone_risk": zone_risk,
    }

    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        risk_img = _colorize_risk(zone_map, zone_risk)
        path = os.path.join(output_dir, f"{name}_map.png")
        cv2.imwrite(path, risk_img)
        out["risk_map"] = path

    return out


def _risk_ramp(k: int) -> List[str]:
    """Assign a risk level to each of k index-ordered clusters (low→high index)."""
    if k == 3:
        return ["high", "medium", "low"]
    # For other k, split the ordered clusters into thirds.
    ramp = []
    for i in range(k):
        frac = i / max(1, k - 1)
        ramp.append("high" if frac < 1 / 3 else "medium" if frac < 2 / 3 else "low")
    return ramp


def _colorize_risk(zone_map: np.ndarray, zone_risk: Dict[int, str]) -> np.ndarray:
    """Render the cluster label map as a stoplight risk image."""
    h, w = zone_map.shape
    out = np.full((h, w, 3), 40, dtype=np.uint8)   # no-data = dark grey
    for label, level in zone_risk.items():
        out[zone_map == label] = _RISK_COLORS[level]
    return out


def health_score(index_map: np.ndarray, vmin: float, vmax: float) -> int:
    """Field health as 0..100 from the mean of a health index over its range."""
    valid = index_map[np.isfinite(index_map) & (index_map != 0)]
    if valid.size == 0:
        return 0
    norm = (float(valid.mean()) - vmin) / (vmax - vmin + 1e-9)
    return int(round(float(np.clip(norm, 0.0, 1.0)) * 100))


# ── Report + action plan ─────────────────────────────────────────────────────

def _index_status(key: str, mean: float) -> str:
    """Classify an index mean as good / moderate / poor from its healthy band."""
    spec = INDEX_REGISTRY.get(key)
    if spec is None:
        return "unknown"
    if spec.higher_is_healthier:
        thr = spec.healthy_threshold
        if thr is None:
            return "moderate"
        if mean >= thr:
            return "good"
        return "moderate" if mean >= thr * 0.6 else "poor"
    # Stress index: higher = worse. Flag the top of its range as poor.
    span = spec.vmax - spec.vmin
    if mean <= spec.vmin + 0.33 * span:
        return "good"
    return "moderate" if mean <= spec.vmin + 0.66 * span else "poor"


def generate_report(
    indices: Dict[str, dict],
    risk: Dict,
    primary_index: str,
    band_names: List[str],
    calibrated: bool,
) -> Dict:
    """Build a structured field-health report from indices + risk zones.

    `indices` is the {key: {stats, meta, ...}} map from compute_indices.
    """
    primary_stats = indices.get(primary_index, {}).get("stats", {})
    spec = INDEX_REGISTRY.get(primary_index)
    score = None
    if spec and primary_stats.get("count"):
        score = health_score_from_stats(primary_stats, spec.vmin, spec.vmax)

    # Per-index one-line summaries.
    summaries = []
    flags = []
    for key, entry in indices.items():
        stats = entry.get("stats", {})
        if not stats.get("count"):
            continue
        mean = stats["mean"]
        status = _index_status(key, mean)
        meta = entry.get("meta", {})
        summaries.append({
            "index": key, "name": meta.get("name", key.upper()),
            "mean": mean, "status": status, "category": meta.get("category"),
        })
        flag = _flag_for(key, mean, stats, status)
        if flag:
            flags.append(flag)

    dist = risk.get("distribution", {})
    return {
        "calibrated": calibrated,
        "bands_used": band_names,
        "primary_index": primary_index,
        "health_score": score,
        "health_label": _score_label(score),
        "risk_distribution": dist,
        "risk_summary": (
            f"{int(round(dist.get('high', 0) * 100))}% of the field is high-risk, "
            f"{int(round(dist.get('medium', 0) * 100))}% medium, "
            f"{int(round(dist.get('low', 0) * 100))}% low."
        ),
        "index_summaries": summaries,
        "flags": flags,
    }


def health_score_from_stats(stats: Dict, vmin: float, vmax: float) -> int:
    norm = (stats["mean"] - vmin) / (vmax - vmin + 1e-9)
    return int(round(float(np.clip(norm, 0.0, 1.0)) * 100))


def _score_label(score: Optional[int]) -> str:
    if score is None:
        return "unknown"
    if score >= 70:
        return "healthy"
    if score >= 45:
        return "moderate"
    return "poor"


def _flag_for(key: str, mean: float, stats: Dict, status: str) -> Optional[Dict]:
    """Human-readable issue flag when an index reading is concerning."""
    spec = INDEX_REGISTRY.get(key)
    if spec is None:
        return None
    high_variability = stats.get("std", 0) > 0.18 and spec.higher_is_healthier

    if key in ("ndre", "gci", "reci") and status in ("poor", "moderate"):
        return {"severity": "high" if status == "poor" else "medium",
                "issue": f"Low chlorophyll signal ({spec.name} mean {mean}) — "
                         "possible nitrogen deficiency.", "index": key}
    if key == "ndwi" and mean > 0.0:
        return {"severity": "medium",
                "issue": f"Elevated water index (NDWI mean {mean}) — possible "
                         "waterlogging or standing water.", "index": key}
    if key == "psri" and status in ("poor", "moderate"):
        return {"severity": "medium",
                "issue": f"High senescence signal (PSRI mean {mean}) — crop "
                         "maturing or under stress.", "index": key}
    if key in ("ndvi", "savi", "osavi") and status == "poor":
        return {"severity": "high",
                "issue": f"Low canopy vigor ({spec.name} mean {mean}) — scout "
                         "for pest, disease, or water stress.", "index": key}
    if key == "ndvi" and high_variability:
        return {"severity": "medium",
                "issue": f"Patchy canopy (NDVI std {stats.get('std')}) — uneven "
                         "growth; consider variable-rate management.", "index": key}
    return None


# Action templates keyed to the flag/index signature. Each returns a dict the UI
# can render as a checklist item.
def generate_action_plan(report: Dict, risk: Dict) -> List[Dict]:
    """Prioritised, index-driven action items derived from the report."""
    actions: List[Dict] = []
    dist = risk.get("distribution", {})
    high_pct = int(round(dist.get("high", 0) * 100))

    # 1. Ground-truth the worst zones first.
    if high_pct > 0:
        actions.append({
            "priority": 1 if high_pct >= 15 else 2,
            "title": f"Scout the high-risk zones ({high_pct}% of field)",
            "detail": "Walk the red zones on the risk map and confirm the cause "
                      "(pest, disease, water, or nutrient stress) before treating.",
            "category": "scouting",
        })

    # 2. Index-signature-driven agronomy.
    flags = {f["index"]: f for f in report.get("flags", [])}
    if any(k in flags for k in ("ndre", "gci", "reci")):
        actions.append({
            "priority": 1,
            "title": "Investigate nitrogen status",
            "detail": "Red-edge/green chlorophyll indices are low. Take tissue or "
                      "SPAD samples in affected zones; consider a variable-rate N "
                      "top-dressing guided by the zone map.",
            "category": "nutrient",
        })
    if "ndwi" in flags:
        actions.append({
            "priority": 2,
            "title": "Check drainage / irrigation",
            "detail": "Water index is elevated in parts of the field. Inspect for "
                      "waterlogging, blocked drainage, or irrigation over-application.",
            "category": "water",
        })
    if "psri" in flags:
        actions.append({
            "priority": 3,
            "title": "Verify crop stage vs. senescence",
            "detail": "Senescence signal is high. Confirm whether this is normal "
                      "maturity or early stress; plan harvest/scouting accordingly.",
            "category": "phenology",
        })
    if "ndvi" in flags and flags["ndvi"]["severity"] == "high":
        actions.append({
            "priority": 1,
            "title": "Address low-vigor patches",
            "detail": "Canopy vigor is low. Prioritise irrigation checks and "
                      "pest/disease scouting in the lowest-NDVI areas.",
            "category": "canopy",
        })

    # 3. Always-on monitoring baseline.
    actions.append({
        "priority": 3,
        "title": "Re-fly and compare in 7–10 days",
        "detail": "Capture the field again to track whether zones improve or "
                  "spread, and to measure the effect of any intervention.",
        "category": "monitoring",
    })

    # De-duplicate by title, keep the highest priority, and sort.
    dedup: Dict[str, Dict] = {}
    for a in actions:
        cur = dedup.get(a["title"])
        if cur is None or a["priority"] < cur["priority"]:
            dedup[a["title"]] = a
    ordered = sorted(dedup.values(), key=lambda a: a["priority"])
    for i, a in enumerate(ordered, 1):
        a["order"] = i
    return ordered
