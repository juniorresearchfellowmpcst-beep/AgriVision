"""Turn parsed KML geometry into an ordered list of drone waypoints.

Two cases:
  * The KML already describes the route (Points or a LineString) -> use its
    vertices directly as waypoints, in order.
  * The KML is a field boundary (Polygon) -> fill it with a boustrophedon
    ("lawnmower") survey path at a given line spacing so the multispectral
    camera covers the whole field with consistent overlap.

Geometry is done in a local equirectangular approximation (metres about the
field centroid), which is accurate for field-scale areas (a few km) and keeps
the module dependency-free. Waypoints are returned as lat/lon/alt for the
flight controller.
"""

import math
from typing import Dict, List

_EARTH_RADIUS_M = 6_378_137.0


def _to_local_xy(coords: List[List[float]], lat0: float, lon0: float):
    """Project [lon, lat, alt] to local metres (x=east, y=north) about origin."""
    cos_lat0 = math.cos(math.radians(lat0))
    pts = []
    for lon, lat, _alt in coords:
        x = math.radians(lon - lon0) * _EARTH_RADIUS_M * cos_lat0
        y = math.radians(lat - lat0) * _EARTH_RADIUS_M
        pts.append((x, y))
    return pts


def _to_lonlat(x: float, y: float, lat0: float, lon0: float):
    cos_lat0 = math.cos(math.radians(lat0))
    lon = lon0 + math.degrees(x / (_EARTH_RADIUS_M * cos_lat0))
    lat = lat0 + math.degrees(y / _EARTH_RADIUS_M)
    return lon, lat


def _point_in_polygon(x: float, y: float, poly: List) -> bool:
    """Ray-casting point-in-polygon test in local coordinates."""
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi
        ):
            inside = not inside
        j = i
    return inside


def _survey_path(
    boundary: List[List[float]], spacing_m: float, altitude_m: float
) -> List[Dict]:
    """Generate a lawnmower survey path covering a polygon boundary.

    spacing_m is the distance between adjacent flight lines (set it from the
    camera swath and desired sidelap). Returns waypoints as dicts.
    """
    lat0 = sum(c[1] for c in boundary) / len(boundary)
    lon0 = sum(c[0] for c in boundary) / len(boundary)
    local = _to_local_xy(boundary, lat0, lon0)

    xs = [p[0] for p in local]
    ys = [p[1] for p in local]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)

    waypoints: List[Dict] = []
    seq = 0
    y = min_y
    flip = False
    # Sweep west-east lines from south to north, alternating direction so the
    # drone snakes instead of flying back to the same side each pass.
    while y <= max_y:
        # Find where this horizontal line enters/exits the polygon.
        row = []
        x = min_x
        step = max(spacing_m / 4.0, 1.0)
        while x <= max_x:
            if _point_in_polygon(x, y, local):
                row.append(x)
            x += step
        if row:
            x_start, x_end = (min(row), max(row))
            ordered = [x_end, x_start] if flip else [x_start, x_end]
            for xv in ordered:
                lon, lat = _to_lonlat(xv, y, lat0, lon0)
                waypoints.append(
                    {"seq": seq, "lat": round(lat, 8), "lon": round(lon, 8),
                     "alt": altitude_m}
                )
                seq += 1
            flip = not flip
        y += spacing_m

    return waypoints


def build_mission(
    parsed: Dict,
    altitude_m: float = 60.0,
    line_spacing_m: float = 20.0,
) -> Dict:
    """Build an ordered waypoint mission from parsed KML geometry.

    Args:
        parsed:        output of kml.parse_kml.
        altitude_m:    flight altitude applied to waypoints lacking one.
        line_spacing_m: spacing between survey lines when filling a polygon.

    Returns {source, waypoint_count, distance_m, waypoints:[{seq,lat,lon,alt}]}.
    """
    placemarks = parsed["placemarks"]

    # Prefer an explicit boundary polygon (survey the area); otherwise honour an
    # explicit path/points route as given.
    polygon = next((p for p in placemarks if p["type"] == "polygon"), None)
    if polygon is not None:
        waypoints = _survey_path(polygon["coordinates"], line_spacing_m, altitude_m)
        source = "polygon-survey"
    else:
        source = "explicit-path"
        waypoints = []
        seq = 0
        for pm in placemarks:
            if pm["type"] not in ("point", "path"):
                continue
            for lon, lat, alt in pm["coordinates"]:
                waypoints.append({
                    "seq": seq,
                    "lat": round(lat, 8),
                    "lon": round(lon, 8),
                    "alt": alt if alt else altitude_m,
                })
                seq += 1

    if not waypoints:
        raise ValueError("Could not derive any waypoints from the KML.")

    return {
        "source": source,
        "altitude_m": altitude_m,
        "line_spacing_m": line_spacing_m if source == "polygon-survey" else None,
        "waypoint_count": len(waypoints),
        "distance_m": round(_path_length(waypoints), 2),
        "waypoints": waypoints,
    }


def _path_length(waypoints: List[Dict]) -> float:
    """Total ground distance along the waypoint sequence, in metres (haversine)."""
    total = 0.0
    for a, b in zip(waypoints, waypoints[1:]):
        total += _haversine(a["lat"], a["lon"], b["lat"], b["lon"])
    return total


def _haversine(lat1, lon1, lat2, lon2) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlam / 2) ** 2
    return 2 * _EARTH_RADIUS_M * math.asin(math.sqrt(a))
