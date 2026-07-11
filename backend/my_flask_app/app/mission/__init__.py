"""Drone mission planning from uploaded KML files.

    kml.parse_kml(text)      -> structured geometry (points / path / polygon)
    planner.build_mission(g) -> ordered lat/lon/alt waypoints for the drone

A LineString/Point KML is used as an explicit path; a Polygon boundary is
filled with a lawnmower survey path so the whole field is imaged.
"""

from .kml import parse_kml
from .planner import build_mission

__all__ = ["parse_kml", "build_mission"]
