"""Turning pixels in a capture into coordinates the drone can fly to.

A spray prescription is born in image space — "this blob of pixels is severely
affected" — and has to end up as latitude/longitude, or it is a picture rather
than a plan. The conversion is a nadir pinhole model:

    ground width covered = 2 · altitude · tan(FOV / 2)
    metres per pixel     = ground width / image width          (the GSD)

with the aircraft's position at the image centre and the top of the image
pointing along its heading.

Accuracy notes an operator should know, and the reason every result carries an
``assumptions`` block:

  * it assumes a level, nadir-pointing camera — a gimbal that was tilted, or a
    sharp bank, shifts the footprint;
  * it assumes flat ground at the altitude reported by the autopilot (which is
    height above *launch*, not above the canopy under the aircraft);
  * with no heading available we fall back to north-up, which is right only if
    the aircraft happened to be flying north.

None of that stops the prescription being useful — a spray boom is a metre or
two wide anyway — but it is why the app asks the operator to confirm before
anything opens a valve.
"""

from __future__ import annotations

import math
from typing import Dict, Optional, Tuple

# Metres per degree of latitude (WGS-84 mean). Good to ~0.1% over a field.
_M_PER_DEG_LAT = 111_320.0


def ground_sample_distance(
    alt_m: float, fov_deg: float, image_width_px: int
) -> Optional[float]:
    """Metres of ground per pixel, or None when the inputs can't give one."""
    try:
        alt = float(alt_m)
        fov = float(fov_deg)
        width = int(image_width_px)
    except (TypeError, ValueError):
        return None
    if alt <= 0 or not 0 < fov < 180 or width <= 0:
        return None
    ground_width = 2.0 * alt * math.tan(math.radians(fov) / 2.0)
    return ground_width / float(width)


def offset_latlon(
    lat: float, lon: float, north_m: float, east_m: float
) -> Tuple[float, float]:
    """Move a coordinate by a local north/east offset in metres."""
    new_lat = lat + (north_m / _M_PER_DEG_LAT)
    # Longitude degrees shrink with latitude; use the *original* latitude's
    # cosine — over a field the difference is nanometres, and clamping keeps
    # the division safe if someone ever flies this near a pole.
    cos_lat = max(math.cos(math.radians(lat)), 1e-6)
    new_lon = lon + (east_m / (_M_PER_DEG_LAT * cos_lat))
    return new_lat, new_lon


def pixel_to_latlon(
    px: float,
    py: float,
    image_size: Tuple[int, int],
    center_lat: float,
    center_lon: float,
    gsd_m: float,
    heading_deg: Optional[float] = None,
) -> Tuple[float, float]:
    """Coordinate of one pixel, given where the aircraft was when it fired.

    Args:
        px, py:      pixel column/row.
        image_size:  ``(width, height)`` of the frame.
        center_lat/lon: aircraft position — the image centre.
        gsd_m:       metres per pixel from :func:`ground_sample_distance`.
        heading_deg: aircraft heading, clockwise from north. ``None`` means
                     north-up.
    """
    width, height = image_size
    # Image y grows downward, so a pixel above the centre is *ahead* of the
    # aircraft — hence the sign flip. Getting this backwards mirrors the whole
    # prescription front-to-back, which is the kind of bug that sprays the
    # healthy half of the field.
    forward_m = ((height / 2.0) - float(py)) * gsd_m
    right_m = (float(px) - (width / 2.0)) * gsd_m

    heading = math.radians(float(heading_deg or 0.0))
    north_m = forward_m * math.cos(heading) - right_m * math.sin(heading)
    east_m = forward_m * math.sin(heading) + right_m * math.cos(heading)

    return offset_latlon(center_lat, center_lon, north_m, east_m)


class Georeferencer:
    """Pixel → lat/lon for one capture, plus the assumptions it rests on."""

    def __init__(
        self,
        image_size: Tuple[int, int],
        lat: Optional[float],
        lon: Optional[float],
        alt_m: Optional[float],
        fov_deg: Optional[float],
        heading_deg: Optional[float] = None,
    ):
        self.image_size = image_size
        self.lat = lat
        self.lon = lon
        self.alt_m = alt_m
        self.fov_deg = fov_deg
        self.heading_deg = heading_deg
        self.gsd_m = ground_sample_distance(alt_m, fov_deg, image_size[0]) \
            if (alt_m and fov_deg) else None

    @property
    def can_georeference(self) -> bool:
        """True when a patch of pixels can become a waypoint."""
        return (
            self.lat is not None
            and self.lon is not None
            and self.gsd_m is not None
            and self.gsd_m > 0
        )

    def area_m2_per_pixel(self) -> Optional[float]:
        return self.gsd_m ** 2 if self.gsd_m else None

    def to_latlon(self, px: float, py: float) -> Optional[Tuple[float, float]]:
        if not self.can_georeference:
            return None
        return pixel_to_latlon(
            px, py, self.image_size, self.lat, self.lon, self.gsd_m, self.heading_deg
        )

    def describe(self) -> Dict:
        """What the caller should tell the operator about these numbers."""
        missing = []
        if self.lat is None or self.lon is None:
            missing.append("no GPS position on the capture (was the drone linked?)")
        if not self.alt_m:
            missing.append("no altitude on the capture")
        if not self.fov_deg:
            missing.append("the camera's field of view is not set")

        return {
            "georeferenced": self.can_georeference,
            "gsd_m": round(self.gsd_m, 4) if self.gsd_m else None,
            "coverage_m": (
                [
                    round(self.gsd_m * self.image_size[0], 2),
                    round(self.gsd_m * self.image_size[1], 2),
                ]
                if self.gsd_m
                else None
            ),
            "heading_deg": self.heading_deg,
            "heading_assumed_north": self.heading_deg is None,
            "missing": missing,
            "assumptions": [
                "Nadir (straight-down) camera over level ground.",
                "Altitude is height above the launch point, not above the canopy.",
            ] if self.can_georeference else [],
        }
