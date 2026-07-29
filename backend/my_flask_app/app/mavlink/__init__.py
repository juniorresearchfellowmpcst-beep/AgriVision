"""MAVLink integration — talks to a flight controller or a SITL simulator.

    link                      the process-wide MavlinkLink (connect, telemetry,
                              mission upload, arm/takeoff/RTL/land)
    build_mission_items(...)  AgriVision waypoints -> MAVLink mission items

The HTTP surface lives in ``app/api/routes/mavlink_routes.py`` and the
orchestration (load a saved mission, upload it, launch it) in
``app/services/mavlink_service.py``.
"""

from .link import MavlinkError, MavlinkLink, link
from .mission_items import build_mission_items, normalise_waypoints, summarise

__all__ = [
    "MavlinkError",
    "MavlinkLink",
    "link",
    "build_mission_items",
    "normalise_waypoints",
    "summarise",
]
