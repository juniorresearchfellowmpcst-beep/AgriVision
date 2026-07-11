"""Parse drone-mission KML files uploaded from the frontend.

KML stores geographic geometry as `<coordinates>` of `lon,lat[,alt]` tuples
(note: longitude first). A mission file can describe the flight in a few ways:

  * Point placemarks       -> explicit individual waypoints
  * a LineString           -> an ordered flight path the drone follows
  * a Polygon              -> a field boundary to survey (see planner.py, which
                             fills it with a lawnmower path)

The parser is namespace-agnostic (KML files vary: kml/2.2, google earth, etc.)
and depends only on the standard library.
"""

import xml.etree.ElementTree as ET
from typing import Dict, List


def _local(tag: str) -> str:
    """Strip the XML namespace: '{ns}Point' -> 'point'."""
    return tag.split("}")[-1].lower()


def _parse_coord_text(text: str) -> List[List[float]]:
    """Parse a KML <coordinates> blob into [[lon, lat, alt], ...].

    Handles arbitrary whitespace/newlines between tuples and an optional
    altitude. Reorders to [lon, lat, alt] as stored in KML.
    """
    coords: List[List[float]] = []
    for token in text.replace("\n", " ").split():
        parts = token.split(",")
        if len(parts) < 2:
            continue
        try:
            lon, lat = float(parts[0]), float(parts[1])
            alt = float(parts[2]) if len(parts) >= 3 else 0.0
        except ValueError:
            continue
        coords.append([lon, lat, alt])
    return coords


def _find_child(elem, name: str):
    for child in elem:
        if _local(child.tag) == name:
            return child
    return None


def _iter(elem, name: str):
    for child in elem.iter():
        if _local(child.tag) == name:
            yield child


def parse_kml(content: str) -> Dict:
    """Parse KML text into structured geometry.

    Returns:
        {
          "placemarks": [
            {"name": str, "type": "point|path|polygon",
             "coordinates": [[lon, lat, alt], ...]}
          ],
          "counts": {"point": n, "path": n, "polygon": n}
        }

    Raises ValueError on malformed XML.
    """
    try:
        root = ET.fromstring(content)
    except ET.ParseError as exc:
        raise ValueError(f"Invalid KML/XML: {exc}") from exc

    placemarks: List[Dict] = []
    counts = {"point": 0, "path": 0, "polygon": 0}

    for pm in _iter(root, "placemark"):
        name_el = _find_child(pm, "name")
        name = (name_el.text or "").strip() if name_el is not None else ""

        # A placemark holds one geometry; detect which.
        point = next(_iter(pm, "point"), None)
        line = next(_iter(pm, "linestring"), None)
        polygon = next(_iter(pm, "polygon"), None)

        if point is not None:
            coord_el = _find_child(point, "coordinates")
            geom_type = "point"
        elif line is not None:
            coord_el = _find_child(line, "coordinates")
            geom_type = "path"
        elif polygon is not None:
            # Use the outer boundary ring of the polygon.
            coord_el = next(_iter(polygon, "coordinates"), None)
            geom_type = "polygon"
        else:
            continue

        if coord_el is None or not (coord_el.text or "").strip():
            continue

        coords = _parse_coord_text(coord_el.text)
        if not coords:
            continue

        placemarks.append({"name": name, "type": geom_type, "coordinates": coords})
        counts[geom_type] += 1

    if not placemarks:
        raise ValueError("No usable Point/LineString/Polygon geometry found in KML.")

    return {"placemarks": placemarks, "counts": counts}
