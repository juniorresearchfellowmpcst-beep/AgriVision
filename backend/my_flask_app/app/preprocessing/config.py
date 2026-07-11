"""Sensor, panel and pipeline defaults for multispectral preprocessing.

These defaults describe a common 5-band agricultural multispectral camera
(e.g. MicaSense RedEdge / Altum style). Override any of them per-capture when
you call the pipeline so the module works with other sensors too.
"""

from dataclasses import dataclass, field
from typing import Dict, List


# Canonical band order used across the pipeline. The reference band for
# alignment is chosen from this list (green is a good default: sharp and
# high-signal for most crops).
DEFAULT_BANDS: List[str] = ["blue", "green", "red", "red_edge", "nir"]

# Known hemispherical reflectance of the calibration (reference) panel per band.
# Manufacturer calibration certificates give these values. The generic ~0.5
# grey panel below is only a placeholder — always pass the real values from the
# panel's certificate for quantitative work.
DEFAULT_PANEL_REFLECTANCE: Dict[str, float] = {
    "blue": 0.50,
    "green": 0.50,
    "red": 0.50,
    "red_edge": 0.50,
    "nir": 0.50,
}


@dataclass
class SensorConfig:
    """Radiometric properties of the camera needed to normalise raw pixels."""

    # Camera black level (dark offset) per band, in raw digital numbers (DN).
    # Subtracted before any radiometric scaling. Read it from image metadata
    # when available; 0 disables the correction.
    black_level: Dict[str, float] = field(default_factory=dict)

    # Bit depth of the raw imagery. Used to know the theoretical DN ceiling
    # and to flag saturated pixels.
    bit_depth: int = 16

    # Fraction of the DN ceiling above which a pixel is treated as saturated
    # and excluded from panel statistics.
    saturation_fraction: float = 0.99


@dataclass
class PanelConfig:
    """How to find the panel in the panel photo and what it reflects."""

    reflectance: Dict[str, float] = field(
        default_factory=lambda: dict(DEFAULT_PANEL_REFLECTANCE)
    )

    # Optional explicit region of interest for the panel, per band or shared.
    # (x, y, w, h) in pixels. When None the pipeline auto-detects the panel.
    roi: Dict[str, tuple] = field(default_factory=dict)

    # When auto-detecting, ignore the outer border of the detected panel by
    # this fraction on every side to avoid edge/shadow contamination.
    roi_shrink: float = 0.15


@dataclass
class AlignmentConfig:
    """Band co-registration behaviour."""

    reference_band: str = "green"

    # "homography" handles perspective/parallax between lenses; "affine" is
    # faster and steadier when the scene is far and flat.
    warp_mode: str = "homography"

    # ECC refinement settings.
    ecc_iterations: int = 200
    ecc_epsilon: float = 1e-6
    # Number of gaussian-pyramid levels for coarse-to-fine ECC.
    pyramid_levels: int = 4

    # Minimum normalised alignment score (0..1) for a band to count as
    # "cleanly aligned" in the quality report.
    min_alignment_score: float = 0.65


@dataclass
class PipelineConfig:
    """Top-level configuration bundle passed through the pipeline."""

    bands: List[str] = field(default_factory=lambda: list(DEFAULT_BANDS))
    sensor: SensorConfig = field(default_factory=SensorConfig)
    panel: PanelConfig = field(default_factory=PanelConfig)
    alignment: AlignmentConfig = field(default_factory=AlignmentConfig)

    # Reflectance values above this are clipped; real reflectance is <= 1.0 but
    # specular hotspots can overshoot, so allow a little headroom.
    reflectance_clip: float = 1.5

    def max_dn(self) -> int:
        return (2 ** self.sensor.bit_depth) - 1
