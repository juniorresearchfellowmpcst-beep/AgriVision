"""Targeted (variable-rate) spraying from a multispectral capture.

The saving this module exists for: a blanket pesticide pass treats the whole
block, while a prescription built from the drone's own imagery treats only the
part of it that is actually affected.

    app.spray.prescription — K-means over a vegetation index -> severe /
                             moderate / healthy zones, sprayable patches, and
                             the costed options the operator chooses between
    app.spray.hotspot_zones — the same thing for a plain RGB survey: K-means
                             over the geotagged CNN detections themselves,
                             emitted in the prescription schema so the mission
                             builder cannot tell the two apart
    app.spray.geo          — pixels -> lat/lon (nadir pinhole model)
    app.spray.mission      — chosen patches -> a MAVLink mission that opens
                             and closes the valve in the right places

The operator is always the one who decides: the backend produces options and
the numbers behind them, and nothing is uploaded to the aircraft until the app
sends back an explicit choice.
"""

from .geo import Georeferencer, ground_sample_distance, offset_latlon, pixel_to_latlon
from .hotspot_zones import HotspotError, cluster_detections, hotspot_geojson
from .mission import (
    CMD_DO_SET_RELAY,
    CMD_DO_SET_SERVO,
    CMD_DO_SPRAYER,
    MECHANISMS,
    build_spray_mission,
    patch_passes,
    spray_config,
    summarise_spray,
)
from .prescription import (
    DEFAULT_DOSE_L_PER_HA,
    DEFAULT_MODERATE_RATE,
    SEVERITY_ORDER,
    PrescriptionError,
    patches_for_levels,
    prescribe,
)

__all__ = [
    "Georeferencer",
    "HotspotError",
    "cluster_detections",
    "hotspot_geojson",
    "ground_sample_distance",
    "offset_latlon",
    "pixel_to_latlon",
    "CMD_DO_SPRAYER",
    "CMD_DO_SET_SERVO",
    "CMD_DO_SET_RELAY",
    "MECHANISMS",
    "build_spray_mission",
    "patch_passes",
    "spray_config",
    "summarise_spray",
    "DEFAULT_DOSE_L_PER_HA",
    "DEFAULT_MODERATE_RATE",
    "SEVERITY_ORDER",
    "PrescriptionError",
    "patches_for_levels",
    "prescribe",
]
