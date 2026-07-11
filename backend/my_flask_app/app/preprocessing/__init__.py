"""Multispectral image preprocessing.

Turns raw drone multispectral captures into analysis-ready reflectance data:

  * reflectance calibration from a calibration-panel photo (reflectance.py)
  * per-band co-registration so bands line up cleanly (alignment.py)
  * mosaic / orthomosaic assembly (orthomosaic.py)

Typical use:

    from app.preprocessing import preprocess_capture, PipelineConfig

    report = preprocess_capture(band_paths, panel_paths, out_dir)
    if report["alignment"]["aligned_cleanly"]:
        stack = report["_aligned_stack"]
"""

from .config import (
    AlignmentConfig,
    PanelConfig,
    PipelineConfig,
    SensorConfig,
    DEFAULT_BANDS,
    DEFAULT_PANEL_REFLECTANCE,
)
from .io import BandStack, read_band_stack, save_stack, save_false_color
from .pipeline import preprocess_capture, preprocess_capture_dir
from .alignment import align_stack
from .reflectance import compute_scale_factors, apply_reflectance, pseudo_reflectance
from .orthomosaic import stitch_mosaic, run_external_odm, odm_available
from .indices import (
    compute_index,
    compute_indices,
    INDEX_BANDS,
    INDEX_REGISTRY,
    list_indices,
    available_indices,
)
from .zoning import kmeans_zones, zone_index_map
from .risk import risk_zones, generate_report, generate_action_plan
from .analysis import analyze_images

__all__ = [
    "PipelineConfig",
    "SensorConfig",
    "PanelConfig",
    "AlignmentConfig",
    "DEFAULT_BANDS",
    "DEFAULT_PANEL_REFLECTANCE",
    "BandStack",
    "read_band_stack",
    "save_stack",
    "save_false_color",
    "preprocess_capture",
    "preprocess_capture_dir",
    "align_stack",
    "compute_scale_factors",
    "apply_reflectance",
    "stitch_mosaic",
    "run_external_odm",
    "odm_available",
    "compute_index",
    "compute_indices",
    "INDEX_BANDS",
    "INDEX_REGISTRY",
    "list_indices",
    "available_indices",
    "pseudo_reflectance",
    "kmeans_zones",
    "zone_index_map",
    "risk_zones",
    "generate_report",
    "generate_action_plan",
    "analyze_images",
]
