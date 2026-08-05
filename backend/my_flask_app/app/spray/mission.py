"""Turning a spray prescription into a flyable, valve-actuating mission.

A survey mission is a list of places to *be*. A spray mission is a list of
places to be **with the pump in a particular state**, and getting that wrong in
either direction is expensive: a valve left open across the healthy half of the
block throws away the saving the prescription just found, and a valve that
never opens flies a perfect pattern over an untreated field.

Layout produced::

    seq 0    NAV_WAYPOINT          home
    seq 1    NAV_TAKEOFF           climb to spray altitude
    seq 2    DO_CHANGE_SPEED       spray pass speed
    per patch:
        NAV_WAYPOINT              approach the patch, pump still OFF
        <pump ON at this patch's rate>
        NAV_WAYPOINT × n          boustrophedon passes across the patch
        <pump OFF>
    last     NAV_RETURN_TO_LAUNCH

**How the pump is actuated is rig-specific**, so it is configuration, not an
assumption (set in ``.env``):

    SPRAY_MECHANISM=sprayer   ArduPilot's built-in crop sprayer (DO_SPRAYER).
                              On/off only — the pump rate is a vehicle
                              parameter, not a mission argument.
    SPRAY_MECHANISM=servo     A servo-driven flow valve (DO_SET_SERVO). PWM is
                              interpolated between the closed and open values,
                              so this is the one mechanism that can genuinely
                              fly a *variable* rate.
    SPRAY_MECHANISM=relay     A relay-switched pump (DO_SET_RELAY). On/off.

That distinction is surfaced as ``variable_rate`` rather than hidden, because
the pesticide saving quoted to the farmer must match what the hardware can
actually do: on an on/off rig, moderate zones get the full rate and the saving
comes only from the ground that is skipped.

No pymavlink import here — the shape of a spray mission is unit-testable with
no vehicle and no optional dependency, exactly like
:mod:`app.mavlink.mission_items`.
"""

from __future__ import annotations

import math
import os
from typing import Dict, List, Optional, Tuple

from app.mavlink.mission_items import (
    CMD_DO_CHANGE_SPEED,
    CMD_NAV_RETURN_TO_LAUNCH,
    CMD_NAV_TAKEOFF,
    CMD_NAV_WAYPOINT,
    FRAME_GLOBAL,
    FRAME_GLOBAL_RELATIVE_ALT,
)

from .geo import offset_latlon

# MAVLink command ids, inlined (see module docstring).
CMD_DO_SET_RELAY = 181       # common: param1 relay number, param2 0/1
CMD_DO_SET_SERVO = 183       # common: param1 channel, param2 PWM
CMD_DO_SPRAYER = 216         # ardupilotmega: param1 0=off 1=on

MECHANISMS = ("sprayer", "servo", "relay")

# Spray defaults, all overridable from the environment.
DEFAULT_MECHANISM = "sprayer"
DEFAULT_SERVO_CHANNEL = 9
DEFAULT_SERVO_OFF_PWM = 1000
DEFAULT_SERVO_ON_PWM = 2000
DEFAULT_RELAY_NUMBER = 0
DEFAULT_SWATH_M = 3.0        # boom/nozzle width on the ground
DEFAULT_SPRAY_ALT_M = 3.0    # spraying is done low — this is not survey height
DEFAULT_SPRAY_SPEED_MS = 3.0


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def spray_config() -> Dict:
    """The rig's spray hardware settings, read from the environment."""
    mechanism = str(os.environ.get("SPRAY_MECHANISM", DEFAULT_MECHANISM)).lower().strip()
    if mechanism not in MECHANISMS:
        mechanism = DEFAULT_MECHANISM

    return {
        "mechanism": mechanism,
        "servo_channel": _env_int("SPRAY_SERVO_CHANNEL", DEFAULT_SERVO_CHANNEL),
        "servo_off_pwm": _env_int("SPRAY_SERVO_OFF_PWM", DEFAULT_SERVO_OFF_PWM),
        "servo_on_pwm": _env_int("SPRAY_SERVO_ON_PWM", DEFAULT_SERVO_ON_PWM),
        "relay_number": _env_int("SPRAY_RELAY_NUMBER", DEFAULT_RELAY_NUMBER),
        "swath_m": _env_float("SPRAY_SWATH_M", DEFAULT_SWATH_M),
        "spray_altitude_m": _env_float("SPRAY_ALTITUDE_M", DEFAULT_SPRAY_ALT_M),
        "spray_speed_ms": _env_float("SPRAY_SPEED_MS", DEFAULT_SPRAY_SPEED_MS),
        # Only a proportional valve can fly a reduced rate over the moderate
        # zones; everything else is a switch.
        "variable_rate": mechanism == "servo",
    }


def patch_passes(
    lat: float,
    lon: float,
    radius_m: float,
    swath_m: float,
    heading_deg: float = 0.0,
) -> List[Tuple[float, float]]:
    """Coverage passes across one circular patch, as ``(lat, lon)`` points.

    A boustrophedon (back-and-forth) inside the patch circle, spaced one swath
    apart. A patch narrower than the swath needs no pattern at all — a single
    pass through the middle covers it, and adding lines there just makes the
    aircraft fidget over a two-metre spot.

    Always returns at least an entry and an exit point: the caller opens the
    valve after the first point, so a patch reduced to one waypoint would be
    "sprayed" without the aircraft ever moving through it.
    """
    radius = max(float(radius_m or 0.0), 0.0)
    swath = max(float(swath_m or DEFAULT_SWATH_M), 0.5)
    heading = math.radians(float(heading_deg or 0.0))

    def to_latlon(along_m: float, across_m: float) -> Tuple[float, float]:
        # 'along' runs with the heading, 'across' to its right.
        north = along_m * math.cos(heading) - across_m * math.sin(heading)
        east = along_m * math.sin(heading) + across_m * math.cos(heading)
        return offset_latlon(lat, lon, north, east)

    if radius <= swath / 2.0:
        half = max(radius, swath / 2.0)
        return [to_latlon(-half, 0.0), to_latlon(half, 0.0)]

    passes: List[Tuple[float, float]] = []
    lines = max(1, int(math.ceil((2.0 * radius) / swath)))
    # Centre the pass lines on the patch rather than starting at its edge.
    start = -((lines - 1) * swath) / 2.0

    for i in range(lines):
        across = start + i * swath
        # Chord half-length of the circle at this offset.
        half = math.sqrt(max(radius ** 2 - across ** 2, 0.0))
        if half < 0.5:
            half = 0.5
        ends = [(-half, across), (half, across)]
        if i % 2:  # alternate direction so the aircraft doesn't fly back empty
            ends.reverse()
        passes.extend(to_latlon(along, cross) for along, cross in ends)

    return passes


def pump_commands(on: bool, rate: float, config: Dict) -> List[Dict]:
    """The command(s) that open or close the valve, for this rig."""
    mechanism = config["mechanism"]

    if mechanism == "servo":
        off_pwm = config["servo_off_pwm"]
        on_pwm = config["servo_on_pwm"]
        # Interpolate: a 0.6 rate is 60% of the way from closed to fully open.
        pwm = off_pwm + (on_pwm - off_pwm) * max(0.0, min(1.0, rate)) if on else off_pwm
        return [{
            "command": CMD_DO_SET_SERVO,
            "param1": float(config["servo_channel"]),
            "param2": float(int(round(pwm))),
        }]

    if mechanism == "relay":
        return [{
            "command": CMD_DO_SET_RELAY,
            "param1": float(config["relay_number"]),
            "param2": 1.0 if on else 0.0,
        }]

    return [{"command": CMD_DO_SPRAYER, "param1": 1.0 if on else 0.0}]


def build_spray_mission(
    targets: List[Dict],
    altitude_m: Optional[float] = None,
    speed_ms: Optional[float] = None,
    home_lat: Optional[float] = None,
    home_lon: Optional[float] = None,
    return_to_launch: bool = True,
    heading_deg: float = 0.0,
    config: Optional[Dict] = None,
    moderate_rate: float = 0.6,
) -> Dict:
    """Build the MAVLink item list for a targeted spray run.

    Args:
        targets: patches to treat — ``{lat, lon, radius_m, severity}``.
        altitude_m: spray height above launch (low; defaults to the rig's).
        speed_ms: pass speed.
        home_lat/home_lon: vehicle home; falls back to the first target.
        heading_deg: direction the coverage passes run.
        moderate_rate: valve opening for moderate patches, 0..1. Forced to 1.0
            on an on/off rig, because pretending otherwise would overstate the
            saving quoted to the farmer.

    Returns ``{items, summary}``.

    Raises:
        ValueError: when there is nothing sprayable to fly.
    """
    config = config or spray_config()

    usable = [
        t for t in (targets or [])
        if t.get("lat") is not None and t.get("lon") is not None
    ]
    if not usable:
        raise ValueError(
            "None of the selected patches have coordinates, so there is "
            "nothing to fly. The capture needs a GPS fix and a camera field of "
            "view before a prescription can become a spray run."
        )

    altitude = float(altitude_m if altitude_m is not None else config["spray_altitude_m"])
    if altitude <= 0:
        raise ValueError("Spray altitude must be greater than 0.")
    speed = float(speed_ms if speed_ms is not None else config["spray_speed_ms"])

    if not config["variable_rate"]:
        moderate_rate = 1.0

    home_lat = float(home_lat) if home_lat is not None else float(usable[0]["lat"])
    home_lon = float(home_lon) if home_lon is not None else float(usable[0]["lon"])

    items: List[Dict] = []

    def add(command, lat=0.0, lon=0.0, alt=0.0, frame=FRAME_GLOBAL_RELATIVE_ALT, **params):
        items.append({
            "seq": len(items),
            "frame": frame,
            "command": int(command),
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

    add(CMD_NAV_WAYPOINT, home_lat, home_lon, 0.0, frame=FRAME_GLOBAL)
    add(CMD_NAV_TAKEOFF, home_lat, home_lon, altitude)
    if speed > 0:
        add(CMD_DO_CHANGE_SPEED, param1=1.0, param2=speed, param3=-1.0)

    # Safety: make sure the valve is shut before the run starts. A pump left
    # open by a previous flight would otherwise spray the whole transit.
    for pump in pump_commands(False, 0.0, config):
        add(pump["command"], **{k: v for k, v in pump.items() if k != "command"})

    swath = config["swath_m"]
    passes_flown = 0
    for target in usable:
        severity = str(target.get("severity") or "severe").lower()
        rate = 1.0 if severity == "severe" else moderate_rate
        radius = float(target.get("radius_m") or 0.0)
        points = patch_passes(
            float(target["lat"]), float(target["lon"]), radius, swath, heading_deg
        )

        # Approach the first pass point with the pump still closed.
        add(CMD_NAV_WAYPOINT, points[0][0], points[0][1], altitude)
        for pump in pump_commands(True, rate, config):
            add(pump["command"], **{k: v for k, v in pump.items() if k != "command"})

        for lat, lon in points[1:]:
            add(CMD_NAV_WAYPOINT, lat, lon, altitude)
        passes_flown += len(points)

        for pump in pump_commands(False, 0.0, config):
            add(pump["command"], **{k: v for k, v in pump.items() if k != "command"})

    if return_to_launch:
        add(CMD_NAV_RETURN_TO_LAUNCH)

    return {
        "items": items,
        "summary": summarise_spray(items, usable, config, speed),
    }


def summarise_spray(
    items: List[Dict], targets: List[Dict], config: Dict, speed_ms: float
) -> Dict:
    """Human-readable digest of a spray mission for the confirmation screen."""
    spray_commands = {CMD_DO_SPRAYER, CMD_DO_SET_SERVO, CMD_DO_SET_RELAY}
    waypoints = [i for i in items if i["command"] == CMD_NAV_WAYPOINT and i["seq"] > 0]

    distance_m = 0.0
    for previous, current in zip(waypoints, waypoints[1:]):
        distance_m += _distance_m(
            previous["lat"], previous["lon"], current["lat"], current["lon"]
        )

    return {
        "item_count": len(items),
        "nav_waypoints": len(waypoints),
        "patches": len(targets),
        "valve_commands": sum(1 for i in items if i["command"] in spray_commands),
        "mechanism": config["mechanism"],
        "variable_rate": config["variable_rate"],
        "swath_m": config["swath_m"],
        "path_length_m": round(distance_m, 1),
        "estimated_minutes": (
            round(distance_m / max(speed_ms, 0.1) / 60.0, 1) if distance_m else 0.0
        ),
        "has_rtl": any(i["command"] == CMD_NAV_RETURN_TO_LAUNCH for i in items),
    }


def _distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Flat-earth distance — plenty over a single field, and cheap."""
    mean_lat = math.radians((lat1 + lat2) / 2.0)
    north = (lat2 - lat1) * 111_320.0
    east = (lon2 - lon1) * 111_320.0 * math.cos(mean_lat)
    return math.hypot(north, east)
