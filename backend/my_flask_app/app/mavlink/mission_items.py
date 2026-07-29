"""Turn AgriVision waypoints into a MAVLink mission item list.

The planner in :mod:`app.mission.planner` produces plain
``{seq, lat, lon, alt}`` dicts (saved missions only keep ``{lat, lon}``).
A flight controller wants a full *mission*: a home entry, a takeoff, the
survey legs, and a way to get back. This module does that translation and
nothing else — no sockets, no pymavlink import — so the shape of a mission
can be unit-tested without a vehicle attached.

Layout produced (ArduPilot / PX4 convention)::

    seq 0   NAV_WAYPOINT        home position (frame GLOBAL, alt 0)
    seq 1   NAV_TAKEOFF         climb to altitude_m over the launch point
    seq 2   DO_CHANGE_SPEED     cruise speed (only when speed_ms is given)
    seq 3+  NAV_WAYPOINT        one per survey waypoint
    last    NAV_RETURN_TO_LAUNCH

Altitudes are *relative to home* (MAV_FRAME_GLOBAL_RELATIVE_ALT), which is
what the app's "Flight Altitude" setting means to a farmer: metres above the
launch point, not above sea level.
"""

from __future__ import annotations

from typing import Dict, List, Optional

# MAVLink enum values, inlined so this module imports without pymavlink.
FRAME_GLOBAL = 0                 # MAV_FRAME_GLOBAL (alt = MSL)
FRAME_GLOBAL_RELATIVE_ALT = 3    # MAV_FRAME_GLOBAL_RELATIVE_ALT

CMD_NAV_WAYPOINT = 16
CMD_NAV_RETURN_TO_LAUNCH = 20
CMD_NAV_LAND = 21
CMD_NAV_TAKEOFF = 22
CMD_DO_CHANGE_SPEED = 178

MISSION_TYPE_MISSION = 0


def normalise_waypoints(raw: List, default_alt_m: float) -> List[Dict]:
    """Accept the several waypoint shapes the app sends and return a clean list.

    Handles ``{lat, lon, alt}``, ``{lat, lng}``, ``{latitude, longitude}`` and
    ``[lat, lon]`` pairs; anything unparseable is skipped rather than aborting
    the whole mission.
    """
    cleaned: List[Dict] = []
    for entry in raw or []:
        lat = lon = alt = None

        if isinstance(entry, dict):
            lat = entry.get("lat", entry.get("latitude"))
            lon = entry.get("lon", entry.get("lng", entry.get("longitude")))
            alt = entry.get("alt", entry.get("altitude"))
        elif isinstance(entry, (list, tuple)) and len(entry) >= 2:
            lat, lon = entry[0], entry[1]
            alt = entry[2] if len(entry) > 2 else None

        try:
            lat_f = float(lat)
            lon_f = float(lon)
        except (TypeError, ValueError):
            continue

        if not (-90.0 <= lat_f <= 90.0 and -180.0 <= lon_f <= 180.0):
            continue

        try:
            alt_f = float(alt) if alt is not None else float(default_alt_m)
        except (TypeError, ValueError):
            alt_f = float(default_alt_m)
        # A waypoint carrying alt 0 means "no altitude given" here — the
        # KML planner writes 0 for 2-D boundaries.
        if alt_f <= 0:
            alt_f = float(default_alt_m)

        cleaned.append({"lat": lat_f, "lon": lon_f, "alt": alt_f})

    return cleaned


def build_mission_items(
    waypoints: List[Dict],
    altitude_m: float = 30.0,
    home_lat: Optional[float] = None,
    home_lon: Optional[float] = None,
    speed_ms: Optional[float] = None,
    return_to_launch: bool = True,
) -> List[Dict]:
    """Build the ordered mission item dicts for :func:`link.upload_mission`.

    Args:
        waypoints: survey waypoints (already normalised).
        altitude_m: flight altitude above home, in metres.
        home_lat/home_lon: vehicle home; falls back to the first waypoint when
            the link has no position fix yet (SITL before GPS lock).
        speed_ms: cruise speed; ``None`` leaves the vehicle's WPNAV default.
        return_to_launch: append an RTL so the drone comes home by itself.

    Raises:
        ValueError: when there is nothing to fly.
    """
    if not waypoints:
        raise ValueError("Mission needs at least one waypoint.")

    altitude_m = float(altitude_m)
    if altitude_m <= 0:
        raise ValueError("altitude_m must be greater than 0.")

    first = waypoints[0]
    home_lat = float(home_lat) if home_lat is not None else first["lat"]
    home_lon = float(home_lon) if home_lon is not None else first["lon"]

    items: List[Dict] = []

    def add(command, lat, lon, alt, frame=FRAME_GLOBAL_RELATIVE_ALT, **params):
        items.append({
            "seq": len(items),
            "frame": frame,
            "command": command,
            # Only seq 0 is flagged 'current'; autocontinue keeps the vehicle
            # moving through the list without a GCS prod between legs.
            "current": 1 if len(items) == 0 else 0,
            "autocontinue": 1,
            "param1": float(params.get("param1", 0.0)),
            "param2": float(params.get("param2", 0.0)),
            "param3": float(params.get("param3", 0.0)),
            "param4": float(params.get("param4", 0.0)),
            "lat": float(lat),
            "lon": float(lon),
            "alt": float(alt),
        })

    # seq 0 — home. ArduPilot overwrites this with its own home on upload but
    # still requires the slot to exist.
    add(CMD_NAV_WAYPOINT, home_lat, home_lon, 0.0, frame=FRAME_GLOBAL)

    # seq 1 — takeoff to survey altitude over the launch point.
    add(CMD_NAV_TAKEOFF, home_lat, home_lon, altitude_m, param1=0.0)

    if speed_ms and float(speed_ms) > 0:
        # param1=1 -> ground speed, param3=-1 -> leave throttle alone.
        add(
            CMD_DO_CHANGE_SPEED, 0.0, 0.0, 0.0,
            param1=1.0, param2=float(speed_ms), param3=-1.0,
        )

    for wp in waypoints:
        add(CMD_NAV_WAYPOINT, wp["lat"], wp["lon"], wp.get("alt", altitude_m))

    if return_to_launch:
        add(CMD_NAV_RETURN_TO_LAUNCH, 0.0, 0.0, 0.0)

    return items


def summarise(items: List[Dict]) -> Dict:
    """Small human-readable digest of a mission item list, for API responses."""
    nav_waypoints = sum(
        1 for i in items
        if i["command"] == CMD_NAV_WAYPOINT and i["seq"] > 0
    )
    return {
        "item_count": len(items),
        "nav_waypoints": nav_waypoints,
        "has_takeoff": any(i["command"] == CMD_NAV_TAKEOFF for i in items),
        "has_rtl": any(i["command"] == CMD_NAV_RETURN_TO_LAUNCH for i in items),
    }
