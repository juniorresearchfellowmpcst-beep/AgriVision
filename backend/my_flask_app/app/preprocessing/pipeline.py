"""End-to-end preprocessing orchestration for one multispectral capture.

Given the raw band images of a scene plus a calibration-panel capture, produce
an analysis-ready reflectance stack, vegetation indices, and management zones.

    ┌── DATA FLOW (this file is the spine; see docs/PREPROCESSING_DATAFLOW.md) ──┐
    band_paths + panel_paths (dict {band: file})
        │  io.read_band_stack
        ▼
    BandStack (raw DN, shape n×H×W)  ──────────────────────────────┐ panel_stack
        │  reflectance.compute_scale_factors(panel) → scale_factors │
        │  reflectance.apply_reflectance(scene, scale_factors)      │
        ▼                                                           ┘
    BandStack (reflectance 0..1)
        │  alignment.align_stack  → aligned_stack + alignment report
        ▼
    BandStack (aligned reflectance)
        │  indices.compute_indices   → {ndvi,gndvi,ndre} float maps
        │  zoning.zone_index_map     → low/medium/high K-means zones
        ▼
    report dict (+ files on disk) ─► service ─► HTTP response / downstream AI
    └───────────────────────────────────────────────────────────────────────────┘

`preprocess_capture` returns everything downstream code (index maps, disease
detection) needs, plus a report that records exactly what was done so results
are reproducible and auditable.
"""

import os
from typing import Dict, List, Optional

from .config import PipelineConfig
from .io import (
    BandStack,
    read_band_stack,
    save_false_color,
    save_stack,
)
from .reflectance import apply_reflectance, compute_scale_factors
from .alignment import align_stack
from .indices import compute_indices, INDEX_BANDS
from .zoning import zone_index_map


def preprocess_capture(
    band_paths: Dict[str, str],
    panel_paths: Dict[str, str],
    output_dir: str,
    config: Optional[PipelineConfig] = None,
    scene_metadata: Optional[Dict[str, dict]] = None,
    panel_metadata: Optional[Dict[str, dict]] = None,
    save_outputs: bool = True,
    indices: Optional[List[str]] = None,
    zones: int = 0,
    zone_index: str = "ndvi",
) -> Dict:
    """Run reflectance calibration + band alignment for a single capture.

    Args:
        band_paths:  {band: path} for the scene image, one file per band.
        panel_paths: {band: path} for the calibration-panel photo.
        output_dir:  where calibrated bands and the QC preview are written.
        config:      PipelineConfig; defaults to a 5-band setup if omitted.
        scene_metadata / panel_metadata:
                     optional {band: {exposure, gain, black_level}} used to
                     normalise DN before radiometric scaling.
        save_outputs: set False to skip disk writes (e.g. in tests).
        indices:     which vegetation indices to compute (e.g. ["ndvi","ndre"]);
                     None skips index computation.
        zones:       k for K-means management zones (0 = don't zone); 3 gives
                     low/medium/high.
        zone_index:  which computed index to cluster into zones.

    Returns a report dict: {status, reflectance_scale, alignment, indices,
    zones, outputs, ...}.
    """
    config = config or PipelineConfig()
    band_order = config.bands

    # [DATA FLOW 1] disk files -> raw-DN BandStacks (io.read_band_stack).
    panel_stack = read_band_stack(panel_paths, band_order)
    scene_stack = read_band_stack(band_paths, band_order)

    # [DATA FLOW 2] panel photo -> per-band scale factors, then raw DN ->
    # reflectance (reflectance.py). Output: reflectance BandStack (0..1).
    scale_factors = compute_scale_factors(panel_stack, config, panel_metadata)
    reflectance = apply_reflectance(scene_stack, scale_factors, config, scene_metadata)

    # [DATA FLOW 3] reflectance -> co-registered stack + QC report
    # (alignment.py). Output: aligned reflectance BandStack cropped to overlap.
    aligned, align_report = align_stack(reflectance, config.alignment)

    report: Dict = {
        "status": "ok",
        "bands": band_order,
        "reflectance_scale": {
            b: {
                "scale": round(v["scale"], 8),
                "panel_signal": v["panel_signal"],
                "panel_reflectance": v["panel_reflectance"],
                "panel_roi": v["panel_info"]["roi"],
                "panel_auto_detected": v["panel_info"]["auto_detected"],
                "panel_saturated_fraction": v["panel_info"]["saturated_fraction"],
            }
            for b, v in scale_factors.items()
        },
        "alignment": align_report,
        "indices": {},
        "zones": None,
        "outputs": {},
    }

    index_dir = os.path.join(output_dir, "indices") if save_outputs else None

    # [DATA FLOW 4] aligned reflectance -> NDVI/GNDVI/NDRE float maps
    # (indices.py). Each entry keeps a raw "_map" array for the zoning step.
    index_results = {}
    if indices:
        index_results = compute_indices(aligned, names=indices, output_dir=index_dir)
        report["indices"] = {
            name: {k: v for k, v in entry.items() if not k.startswith("_")}
            for name, entry in index_results.items()
        }

    # [DATA FLOW 5] one index map -> low/medium/high K-means zones (zoning.py).
    if zones and zones >= 2:
        if zone_index not in index_results:
            # Ensure the index we want to zone on exists.
            index_results.update(
                compute_indices(aligned, names=[zone_index], output_dir=index_dir)
            )
            report["indices"][zone_index] = {
                k: v for k, v in index_results[zone_index].items()
                if not k.startswith("_")
            }
        zone_result = zone_index_map(
            index_results[zone_index]["_map"],
            k=zones,
            output_dir=index_dir,
            name=zone_index,
        )
        report["zones"] = {k: v for k, v in zone_result.items() if not k.startswith("_")}

    # [DATA FLOW 6] persist reflectance TIFFs + false-colour preview; the
    # in-memory aligned stack is also returned for callers that chain in-process.
    if save_outputs:
        os.makedirs(output_dir, exist_ok=True)
        band_files = save_stack(aligned, output_dir, prefix="reflectance")
        preview = save_false_color(
            aligned, os.path.join(output_dir, "false_color_preview.png")
        )
        report["outputs"] = {"bands": band_files, "preview": preview}

    report["_aligned_stack"] = aligned  # in-memory handle for chained callers
    return report


def preprocess_capture_dir(
    scene_dir: str,
    panel_dir: str,
    output_dir: str,
    config: Optional[PipelineConfig] = None,
    **kwargs,
) -> Dict:
    """Convenience wrapper: discover band files in folders, then preprocess.

    Matches files to bands by name (see io.discover_capture). Useful when a
    capture is a folder of `IMG_xxxx_<n>.tif` files.
    """
    from .io import discover_capture

    config = config or PipelineConfig()
    band_paths = discover_capture(scene_dir, config.bands)
    panel_paths = discover_capture(panel_dir, config.bands)

    missing_scene = [b for b in config.bands if b not in band_paths]
    missing_panel = [b for b in config.bands if b not in panel_paths]
    if missing_scene or missing_panel:
        return {
            "status": "error",
            "message": "Could not match all bands from the folders.",
            "missing_scene_bands": missing_scene,
            "missing_panel_bands": missing_panel,
        }

    return preprocess_capture(
        band_paths, panel_paths, output_dir, config=config, **kwargs
    )
