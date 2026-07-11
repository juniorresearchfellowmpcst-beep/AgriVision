"""One-call analysis of multispectral images picked from the system.

This is the entry point used when there is **no drone / no KML** yet: the user
selects a set of band images from disk, and we run the full crop-monitoring
chain and hand back everything the app needs to render.

    band files ─► (calibrate | pseudo-reflectance) ─► align ─► indices
                 ─► risk zones (high/med/low) ─► report ─► action plan

Unlike `preprocess_capture`, calibration is optional here: with a panel set we
produce true reflectance; without one we fall back to relative pseudo-
reflectance so indices and risk zoning still work (flagged `calibrated: false`).
"""

import os
from typing import Dict, List, Optional

from .config import PipelineConfig
from .io import read_band_stack, save_false_color
from .reflectance import (
    apply_reflectance,
    compute_scale_factors,
    pseudo_reflectance,
)
from .alignment import align_stack
from .indices import INDEX_REGISTRY, available_indices, compute_indices
from .risk import generate_action_plan, generate_report, risk_zones


# Preference order for the index that drives the risk map — first available wins.
_PRIMARY_PREFERENCE = ["ndvi", "osavi", "savi", "evi2", "gndvi", "grvi", "vari"]


def _pick_primary(available: List[str], requested: Optional[str]) -> Optional[str]:
    if requested and requested in available:
        return requested
    for key in _PRIMARY_PREFERENCE:
        if key in available:
            return key
    return available[0] if available else None


def analyze_images(
    band_paths: Dict[str, str],
    output_dir: str,
    config: Optional[PipelineConfig] = None,
    panel_paths: Optional[Dict[str, str]] = None,
    indices: Optional[List[str]] = None,
    primary_index: Optional[str] = None,
    align: bool = True,
    save_outputs: bool = True,
) -> Dict:
    """Analyse a set of band images and return report + risk + action plan.

    Args:
        band_paths:   {band: path} for the scene (subset of the 5 bands is OK).
        output_dir:   where previews/maps are written.
        panel_paths:  {band: path} calibration-panel photo; enables true
                      reflectance. Omit to use relative pseudo-reflectance.
        indices:      which indices to compute; None = all that the bands allow.
        primary_index: index the risk map is based on; None = auto-pick.
        align:        co-register the bands first (recommended for separate
                      per-band files; harmless if already aligned).

    Returns a JSON-safe report dict (no in-memory arrays).
    """
    config = config or PipelineConfig()
    # Only keep the bands we were actually given, preserving canonical order.
    band_order = [b for b in config.bands if b in band_paths]
    if not band_order:
        # Fall back to whatever bands the caller passed, in given order.
        band_order = list(band_paths.keys())
    if not band_order:
        raise ValueError("No band images provided.")

    # [DATA FLOW 1] disk files -> raw BandStack.
    scene = read_band_stack({b: band_paths[b] for b in band_order}, band_order)

    # [DATA FLOW 2] calibrate to reflectance, or relative pseudo-reflectance.
    calibrated = False
    if panel_paths and all(b in panel_paths for b in band_order):
        panel = read_band_stack({b: panel_paths[b] for b in band_order}, band_order)
        scale = compute_scale_factors(panel, config)
        reflectance = apply_reflectance(scene, scale, config)
        calibrated = True
    else:
        reflectance = pseudo_reflectance(scene)

    # [DATA FLOW 3] optional band co-registration.
    alignment_report = None
    if align and len(band_order) > 1:
        reflectance, alignment_report = align_stack(reflectance, config.alignment)

    # [DATA FLOW 4] vegetation indices (all the bands support).
    index_dir = os.path.join(output_dir, "indices") if save_outputs else None
    names = indices or available_indices(reflectance.band_names)
    index_results = compute_indices(reflectance, names=names, output_dir=index_dir)
    if not index_results:
        raise ValueError(
            "No vegetation indices could be computed from the provided bands "
            f"({reflectance.band_names}). At least a red + NIR (or RGB) is needed."
        )

    # [DATA FLOW 5] risk zones on the chosen health index.
    primary = _pick_primary(list(index_results.keys()), primary_index)
    spec = INDEX_REGISTRY.get(primary)
    risk = risk_zones(
        index_results[primary]["_map"],
        higher_is_healthier=spec.higher_is_healthier if spec else True,
        k=3,
        output_dir=index_dir,
        name="risk",
    )

    # Strip in-memory arrays before serialising.
    indices_json = {
        k: {kk: vv for kk, vv in v.items() if not kk.startswith("_")}
        for k, v in index_results.items()
    }
    risk_json = {k: v for k, v in risk.items() if not k.startswith("_")}

    # [DATA FLOW 6] report + action plan.
    report = generate_report(
        index_results, risk, primary, reflectance.band_names, calibrated
    )
    action_plan = generate_action_plan(report, risk)

    outputs = {}
    if save_outputs:
        os.makedirs(output_dir, exist_ok=True)
        outputs["false_color"] = save_false_color(
            reflectance, os.path.join(output_dir, "false_color.png")
        ) if _has_false_color_bands(reflectance.band_names) else None
        outputs["risk_map"] = risk.get("risk_map")
        outputs["index_previews"] = {
            k: v.get("preview") for k, v in index_results.items() if v.get("preview")
        }

    return {
        "status": "ok",
        "calibrated": calibrated,
        "bands_used": reflectance.band_names,
        "primary_index": primary,
        "alignment": alignment_report,
        "report": report,
        "risk": risk_json,
        "action_plan": action_plan,
        "indices": indices_json,
        "outputs": outputs,
    }


def _has_false_color_bands(band_names: List[str]) -> bool:
    return all(b in band_names for b in ("nir", "red", "green"))
