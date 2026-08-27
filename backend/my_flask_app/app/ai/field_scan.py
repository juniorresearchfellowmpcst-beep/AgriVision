"""Field scan: weed detection + crop disease classification on mission frames.

This is what the "low-pace mission" is for. A survey flown high and fast gives
the multispectral pipeline what it needs (where the field is stressed); it does
**not** give enough resolution to say *why*. So the aircraft flies a second,
slow, low pass over the areas that mattered, the RGB camera collects frames,
and each one goes through:

    frame ─┬─► weed detector      (row geometry / appearance)  ─► pressure
           └─► disease classifier (CNN, else canopy signature) ─► condition
                                                                    │
    every frame ────────────────► aggregate ─────────────► field-level answer

Both halves prefer a trained CNN and fall back to an OpenCV heuristic, so the
feature works on a laptop with no model files and gets better the moment one
is dropped in (see ``tools/train_crop_cnn.py``).

The output is deliberately hedged where the evidence is thin: a canopy photo
can show the *pattern* of a problem, and pattern plus crop plus season narrows
it a long way, but it is still screening, not a lab result.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

import cv2
import numpy as np

from . import crop_model, weed_detector
from .canopy import extract_canopy_features
from .crop_kb import diseases_for, get_crop, get_disease
from .weed_kb import pressure_for

# Colours that look alike enough in a canopy photo to score a partial match.
_COLOUR_NEIGHBOURS = {
    "yellow": {"orange"},
    "orange": {"yellow", "brown"},
    "brown": {"orange", "grey"},
    "grey": {"brown", "white"},
    "white": {"grey"},
    "green": set(),
}

# Patterns that are easy to confuse from the air.
_PATTERN_NEIGHBOURS = {
    "spots": {"blotch"},
    "blotch": {"spots", "wilt"},
    "streak": {"spots"},
    "mosaic": {"streak"},
    "coating": {"blotch"},
    "wilt": {"blotch"},
    "chewed": {"spots"},
}


def decode(image_bytes: bytes) -> Optional[np.ndarray]:
    """Decode uploaded image bytes to BGR, or ``None`` when unreadable."""
    if not image_bytes:
        return None
    return cv2.imdecode(np.frombuffer(image_bytes, dtype=np.uint8), cv2.IMREAD_COLOR)


# ── heuristic disease classification ─────────────────────────────────────────

def dominant_signature(features: Dict[str, Any]) -> Dict[str, Any]:
    """Reduce canopy features to the (colour, pattern) the KB speaks in."""
    shares = {
        "yellow": features.get("yellow_fraction", 0.0),
        "orange": features.get("orange_fraction", 0.0),
        "brown": features.get("brown_fraction", 0.0),
        "white": features.get("white_fraction", 0.0),
        "grey": features.get("grey_fraction", 0.0),
    }
    colour, share = max(shares.items(), key=lambda item: item[1])

    affected = features.get("affected_fraction", 0.0)
    spots = features.get("spot_count", 0)
    largest = features.get("largest_lesion_fraction", 0.0)
    elongation = features.get("elongation", 1.0)
    mosaic = features.get("mosaic_score", 0.0)

    if affected < 0.15 and share < 0.06 and spots < 4:
        return {"colour": "green", "pattern": "none", "strength": 0.0, "shares": shares}

    if colour in ("white", "grey") and share >= 0.08:
        pattern = "coating"
    elif mosaic >= 0.9 and shares["yellow"] >= 0.08:
        pattern = "mosaic"
    elif elongation >= 2.5 and spots >= 3:
        pattern = "streak"
    elif largest >= 0.15:
        pattern = "blotch"
    elif spots >= 5:
        pattern = "spots"
    elif affected >= 0.30:
        # Broad discolouration with no discrete lesions reads as collapse
        # rather than infection — wilt, drought, or root trouble.
        pattern = "wilt"
    else:
        pattern = "blotch"

    return {"colour": colour, "pattern": pattern, "strength": round(share, 4), "shares": shares}


def _signature_score(signature: Dict[str, Any], disease: Dict[str, Any]) -> float:
    target = disease.get("signature") or {}
    colour, pattern = target.get("colour"), target.get("pattern")

    if signature["colour"] == colour:
        colour_score = 1.0
    elif colour in _COLOUR_NEIGHBOURS.get(signature["colour"], set()):
        colour_score = 0.5
    else:
        colour_score = 0.0

    if signature["pattern"] == pattern:
        pattern_score = 1.0
    elif pattern in _PATTERN_NEIGHBOURS.get(signature["pattern"], set()):
        pattern_score = 0.4
    else:
        pattern_score = 0.0

    # Colour weighs more: it survives compression and low resolution, while
    # the pattern is the first thing a shaky frame loses.
    return 0.6 * colour_score + 0.4 * pattern_score


def classify_heuristic(
    features: Dict[str, Any], crop: Optional[str]
) -> Dict[str, Any]:
    """Best crop-specific match for a canopy signature, with a modest score."""
    if not features.get("canopy_found"):
        return {
            "condition_id": "general_stress",
            "confidence": 0.2,
            "source": "heuristic",
            "signature": None,
            "low_confidence": True,
        }

    signature = dominant_signature(features)
    if signature["colour"] == "green":
        return {
            "condition_id": "healthy",
            "confidence": round(0.6 + min(0.3, features.get("green_fraction", 0.0) * 0.3), 2),
            "source": "heuristic",
            "signature": signature,
        }

    candidates = diseases_for(crop)
    if not candidates:
        return {
            "condition_id": "general_stress",
            "confidence": 0.35,
            "source": "heuristic",
            "signature": signature,
            "note": "Pick the crop to get a named condition — the same yellowing "
                    "means different things in wheat and in soybean.",
        }

    scored = sorted(
        ((_signature_score(signature, d), d) for d in candidates),
        key=lambda pair: pair[0],
        reverse=True,
    )
    best_score, best = scored[0]
    if best_score <= 0.0:
        return {
            "condition_id": "general_stress",
            "confidence": 0.3,
            "source": "heuristic",
            "signature": signature,
        }

    # Deliberately capped: a canopy photo narrows the field, it does not
    # confirm a pathogen. Anything above ~0.7 from colour and shape alone
    # would be overstating what the evidence supports.
    confidence = round(min(0.7, 0.35 + best_score * 0.35), 2)
    alternatives = [
        {"id": disease["id"], "name": disease["name"], "score": round(score, 2)}
        for score, disease in scored[1:3]
        if score > 0
    ]
    return {
        "condition_id": best["id"],
        "confidence": confidence,
        "source": "heuristic",
        "signature": signature,
        "alternatives": alternatives,
    }


def _severity(condition_id: str, affected_fraction: float) -> Dict[str, Any]:
    if condition_id == "healthy":
        return {"level": "none", "affected_percent": 0}
    percent = int(round(affected_fraction * 100))
    if affected_fraction >= 0.45:
        level = "high"
    elif affected_fraction >= 0.18:
        level = "moderate"
    else:
        level = "low"
    return {"level": level, "affected_percent": percent}


# ── one frame ────────────────────────────────────────────────────────────────

# What a scan is asked to look for. Not cosmetic: each half is a separate pass
# over the frame, so a weed-only survey that skips the disease CNN scans in
# roughly half the time -- which on a live feed is the difference between a
# readout that describes where the aircraft *is* and one that describes where
# it was.
SCAN_TARGETS = ("disease", "weed", "both")

_EMPTY_WEEDS = {
    "weed_coverage": 0.0,
    "vegetation_coverage": 0.0,
    "pressure": {"level": "none", "coverage": 0.0, "percent": 0, "advice": ""},
    "patches": [],
    "method": "not_requested",
    "note": "Weed detection was switched off for this scan.",
}


def scan_frame(
    image: np.ndarray,
    crop: Optional[str] = None,
    want_overlay: bool = True,
    target: str = "both",
) -> Dict[str, Any]:
    """Run weed detection and disease classification on one canopy frame.

    ``target`` selects which half runs: ``"disease"``, ``"weed"`` or
    ``"both"``. The half that is switched off reports zeroes with a ``method``
    of ``not_requested`` rather than being omitted, so a caller reading the
    result never has to guess whether "no weeds" means clean ground or a
    detector that never ran.
    """
    if image is None or getattr(image, "size", 0) == 0:
        return {
            "status": "error",
            "message": "Could not read the image. Send a clear JPG or PNG frame.",
        }

    target = str(target or "both").strip().lower()
    if target not in SCAN_TARGETS:
        target = "both"
    want_weeds = target in ("weed", "both")
    want_disease = target in ("disease", "both")

    crop_entry = get_crop(crop)
    crop_id = crop_entry["id"] if crop_entry else None

    overlay = None
    if want_weeds:
        weeds = weed_detector.detect(image, crop=crop_id)
        overlay = weeds.pop("_overlay", None)
        weeds.pop("_weed_mask", None)
        weeds.pop("_vegetation_mask", None)
    else:
        weeds = dict(_EMPTY_WEEDS)

    features = extract_canopy_features(image)

    if want_disease:
        prediction = crop_model.classify_disease(image, crop_id)
        if prediction is None:
            prediction = classify_heuristic(features, crop_id)
        elif not prediction.get("label_matched"):
            # The model answered with something this app has no entry for. Say
            # so instead of dressing an unmapped label up as a diagnosis.
            prediction["note"] = (
                f"The model returned '{prediction.get('raw_label')}', which is "
                "not one of the conditions this app knows for this crop."
            )
    else:
        prediction = {
            "condition_id": "healthy",
            "confidence": 0.0,
            "source": "not_requested",
            "alternatives": [],
            "note": "Disease detection was switched off for this scan.",
        }

    condition = get_disease(prediction["condition_id"])
    severity = (
        _severity(condition["id"], features.get("affected_fraction", 0.0))
        if want_disease
        else {"level": "none", "affected_percent": 0}
    )

    weed_species = (
        crop_model.classify_weed(image)
        if want_weeds and weeds.get("weed_coverage", 0) > 0.02
        else None
    )

    result = {
        "status": "ok",
        "crop": crop_id,
        "crop_name": crop_entry["name"] if crop_entry else None,
        "target": target,
        "weeds": weeds,
        "weed_species": weed_species,
        "disease": {
            "id": condition["id"],
            "name": condition["name"],
            "pathogen": condition.get("pathogen", ""),
            "symptoms": condition.get("symptoms", []),
            "favours": condition.get("favours", ""),
            "management": condition.get("management", []),
            "severity_note": condition.get("severity_note", ""),
            "confidence": prediction.get("confidence", 0.0),
            "source": prediction.get("source", "heuristic"),
            "alternatives": prediction.get("alternatives", []),
            "note": prediction.get("note", ""),
        },
        "severity": severity,
        "is_healthy": condition["id"] == "healthy",
        "observations": features,
        "actions": build_actions(condition, severity, weeds, crop_entry),
        "disclaimer": (
            "Automated screening from a drone frame — it narrows the "
            "possibilities, it does not confirm a pathogen. Walk the spot and "
            "confirm before applying any chemical."
        ),
    }
    if want_overlay and overlay is not None:
        result["_overlay"] = overlay
    return result


def build_actions(
    condition: Dict[str, Any],
    severity: Dict[str, Any],
    weeds: Dict[str, Any],
    crop_entry: Optional[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """What to do about this frame, worst problem first."""
    actions: List[Dict[str, Any]] = []

    if condition["id"] not in ("healthy",):
        priority = 1 if severity["level"] == "high" else 2
        actions.append({
            "priority": priority,
            "category": "disease",
            "title": f"Confirm {condition['name']} on the ground",
            "detail": (
                (condition.get("symptoms") or [""])[0]
                + ". "
                + (condition.get("management") or [""])[0]
                + "."
            ).strip(". ") + ".",
        })

    pressure = (weeds or {}).get("pressure") or {}
    if pressure.get("level") in ("moderate", "high"):
        actions.append({
            "priority": 1 if pressure["level"] == "high" else 2,
            "category": "weed",
            "title": f"{pressure['level'].title()} weed pressure "
                     f"({pressure.get('percent', 0)}% ground cover)",
            "detail": pressure.get("advice", ""),
        })
        for weed in (weeds.get("likely_weeds") or [])[:1]:
            if isinstance(weed, dict):
                actions.append({
                    "priority": 3,
                    "category": "weed",
                    "title": f"Check for {weed['name']} ({weed.get('local_name', '')})".strip(),
                    "detail": "; ".join(weed.get("control", [])[:2]),
                })

    if not actions:
        actions.append({
            "priority": 3,
            "category": "monitoring",
            "title": "Nothing to act on in this frame",
            "detail": "Canopy is clean and weed pressure is negligible. Re-fly "
                      "in 7–10 days to catch a change early.",
        })

    if crop_entry and crop_entry.get("season"):
        actions.append({
            "priority": 4,
            "category": "context",
            "title": f"{crop_entry['name']} — {crop_entry['season']} crop",
            "detail": crop_entry.get("note", "") or
                      "Match any treatment to the crop stage, not just the symptom.",
        })

    actions.sort(key=lambda action: action["priority"])
    for order, action in enumerate(actions, 1):
        action["order"] = order
    return actions


# ── many frames ──────────────────────────────────────────────────────────────

def aggregate(scans: List[Dict[str, Any]], crop: Optional[str] = None) -> Dict[str, Any]:
    """Roll per-frame scans up into one answer about the field.

    A single frame is an anecdote. What an operator needs after a low pass is
    the field-level picture: how much of it is weedy, which condition keeps
    coming up, and *where* the bad frames were — because those coordinates are
    what the next spray run is aimed at.
    """
    usable = [s for s in scans if s and s.get("status") == "ok"]
    if not usable:
        return {
            "status": "error",
            "message": "No frames could be scanned.",
            "frames": 0,
        }

    weed_coverages = [
        float((s.get("weeds") or {}).get("weed_coverage") or 0.0) for s in usable
    ]
    mean_weed = sum(weed_coverages) / len(weed_coverages)

    condition_counts: Dict[str, Dict[str, Any]] = {}
    for scan in usable:
        disease = scan.get("disease") or {}
        key = disease.get("id") or "general_stress"
        entry = condition_counts.setdefault(
            key,
            {
                "id": key,
                "name": disease.get("name", key),
                "frames": 0,
                "confidence_sum": 0.0,
                "worst_severity": "none",
            },
        )
        entry["frames"] += 1
        entry["confidence_sum"] += float(disease.get("confidence") or 0.0)
        level = (scan.get("severity") or {}).get("level", "none")
        if _severity_rank(level) > _severity_rank(entry["worst_severity"]):
            entry["worst_severity"] = level

    conditions = sorted(
        (
            {
                "id": entry["id"],
                "name": entry["name"],
                "frames": entry["frames"],
                "frame_share": round(entry["frames"] / len(usable), 3),
                "mean_confidence": round(entry["confidence_sum"] / entry["frames"], 2),
                "worst_severity": entry["worst_severity"],
            }
            for entry in condition_counts.values()
        ),
        key=lambda entry: entry["frames"],
        reverse=True,
    )

    diseased = [s for s in usable if not s.get("is_healthy")]
    hotspots = []
    for scan in usable:
        weed_level = ((scan.get("weeds") or {}).get("pressure") or {}).get("level")
        severity_level = (scan.get("severity") or {}).get("level")
        if weed_level != "high" and severity_level != "high":
            continue
        if scan.get("lat") is None or scan.get("lon") is None:
            continue
        hotspots.append({
            "lat": scan["lat"],
            "lon": scan["lon"],
            "frame_id": scan.get("frame_id"),
            "condition": (scan.get("disease") or {}).get("name"),
            "severity": severity_level,
            "weed_pressure": weed_level,
        })

    top = conditions[0] if conditions else None
    dominant = next((c for c in conditions if c["id"] != "healthy"), None)

    summary_parts = [
        f"{len(usable)} frame(s) scanned.",
        f"Weed cover averages {int(round(mean_weed * 100))}% of the ground "
        f"({pressure_for(mean_weed)['level']} pressure).",
    ]
    if dominant:
        summary_parts.append(
            f"{dominant['name']} appears in {int(round(dominant['frame_share'] * 100))}% "
            "of frames."
        )
    else:
        summary_parts.append("No disease pattern stood out across the frames.")

    return {
        "status": "ok",
        "crop": crop,
        "frames": len(usable),
        "weed": {
            **pressure_for(mean_weed),
            "mean_coverage": round(mean_weed, 4),
            "max_coverage": round(max(weed_coverages), 4),
            "frames_above_moderate": sum(1 for c in weed_coverages if c >= 0.08),
        },
        "conditions": conditions,
        "top_condition": top,
        "dominant_problem": dominant,
        "diseased_frames": len(diseased),
        "disease_incidence": round(len(diseased) / len(usable), 3),
        "hotspots": hotspots,
        "summary": " ".join(summary_parts),
        "actions": _aggregate_actions(usable, mean_weed, dominant, crop),
    }


def _severity_rank(level: Optional[str]) -> int:
    return {"none": 0, "low": 1, "moderate": 2, "high": 3}.get(level or "none", 0)


def _aggregate_actions(
    scans: List[Dict[str, Any]],
    mean_weed: float,
    dominant: Optional[Dict[str, Any]],
    crop: Optional[str],
) -> List[Dict[str, Any]]:
    actions: List[Dict[str, Any]] = []
    pressure = pressure_for(mean_weed)

    if pressure["level"] in ("moderate", "high"):
        actions.append({
            "priority": 1 if pressure["level"] == "high" else 2,
            "category": "weed",
            "title": f"Field-wide weed pressure is {pressure['level']} "
                     f"({pressure['percent']}% cover)",
            "detail": pressure["advice"],
        })

    if dominant and dominant["frame_share"] >= 0.3:
        condition = get_disease(dominant["id"])
        actions.append({
            "priority": 1 if dominant["worst_severity"] == "high" else 2,
            "category": "disease",
            "title": f"{dominant['name']} across "
                     f"{int(round(dominant['frame_share'] * 100))}% of the pass",
            "detail": "; ".join(condition.get("management", [])[:2]),
        })
    elif dominant:
        actions.append({
            "priority": 3,
            "category": "disease",
            "title": f"{dominant['name']} in a few frames only",
            "detail": "Localised so far. Walk those spots and decide whether it "
                      "is worth a spot treatment before it spreads.",
        })

    hotspot_count = sum(
        1 for s in scans
        if ((s.get("severity") or {}).get("level") == "high"
            or ((s.get("weeds") or {}).get("pressure") or {}).get("level") == "high")
    )
    if hotspot_count:
        actions.append({
            "priority": 1,
            "category": "spray",
            "title": f"{hotspot_count} hotspot frame(s) worth a targeted pass",
            "detail": "Run a multispectral capture over these spots and build a "
                      "spray prescription rather than treating the whole block.",
        })

    actions.append({
        "priority": 4,
        "category": "monitoring",
        "title": "Re-fly the low pass in 7–10 days",
        "detail": "Change between two passes is the reliable signal — a single "
                  "pass cannot tell a spreading problem from a static one.",
    })

    actions.sort(key=lambda action: action["priority"])
    for order, action in enumerate(actions, 1):
        action["order"] = order
    return actions
