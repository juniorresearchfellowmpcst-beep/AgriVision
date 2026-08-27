"""K-means over geotagged detections, for the RGB-only survey path.

:mod:`app.spray.prescription` clusters *pixels* of a vegetation index, which
needs a red + NIR pair -- a multispectral rig. That is the right tool when the
aircraft carries one, and no tool at all when it carries an ordinary IP camera.

The RGB path produces a different raw material: a trail of geotagged frames,
each with a CNN verdict (which disease, how confident) and a weed-cover
fraction, dropped along the flight line every few seconds. What the operator
needs from that is the same thing the multispectral path gives them -- a map
of *where in this field* the problem is, grouped into patches a boom can fly.

So this module runs K-means over the detections themselves: position in metres
plus a severity score, clustered into zones, ordered worst-first, and emitted
in exactly the schema :func:`app.spray.mission.build_spray_mission` already
consumes. A prescription built here is stored as an ordinary
``SprayPrescription`` and flown by the existing ``/plan`` and ``/execute``
endpoints, unchanged.

Three honest limits, all reported in the result rather than hidden:

  * **A detection is a point, not an outline.** The camera saw a patch of
    ground roughly one frame wide; the aircraft's position is what we know
    precisely. A cluster's radius is therefore derived from how far its member
    frames spread, floored at the swath width -- never claimed to be the true
    edge of an infection.
  * **Unlocated frames cannot be sprayed.** A scan with no GPS fix still counts
    towards the health summary and is excluded from the map, with a count in
    ``skipped_no_fix`` so the difference is visible.
  * **Few detections make a poor map.** Below :data:`MIN_SAMPLES_FOR_KMEANS`
    the module does not pretend to cluster; it emits one patch per detection
    and says so.
"""

from __future__ import annotations

import math
import os
from typing import Any, Dict, List, Optional, Sequence, Tuple

import numpy as np

from .geo import offset_latlon

# Below this, clustering is theatre: three points do not have a structure for
# K-means to find, and the operator is better served by three small patches.
MIN_SAMPLES_FOR_KMEANS = 6

# How wide a single frame's detection is assumed to cover on the ground when
# nothing better is known. A low-flying survey frame is a few metres across;
# this is deliberately conservative so a patch is not under-sprayed at its edge.
DEFAULT_DETECTION_RADIUS_M = 6.0

# Cluster severity ordering. Matches app.spray.prescription so both paths feed
# the same option/economics code.
SEVERITY_ORDER = ("severe", "moderate", "healthy")

# Score bands a cluster mean falls into. Scores are built by _sample_score()
# below and run 0 (clean) to 1 (as bad as this scan can report).
_SEVERE_AT = 0.60
_MODERATE_AT = 0.30

# Weed cover at which a frame counts as fully weed-affected for scoring.
_WEED_FULL_SCALE = 0.25

_SEVERITY_WEIGHT = {"none": 0.0, "low": 0.25, "moderate": 0.6, "high": 1.0}


class HotspotError(ValueError):
    """The detections cannot be turned into a map, with the reason why."""


def _sample_score(sample: Dict[str, Any]) -> float:
    """How bad one scanned frame is, on 0..1.

    Disease and weeds are combined by taking the worse of the two rather than
    averaging them: a frame that is clean of weeds but carrying high-severity
    blast is a frame worth spraying, and an average would dilute it into the
    moderate band where it might be skipped.
    """
    severity = (sample.get("severity") or {}).get("level")
    disease_score = _SEVERITY_WEIGHT.get(str(severity or "none").lower(), 0.0)

    # A confident detection at a given severity is worse than a doubtful one.
    confidence = (sample.get("disease") or {}).get("confidence")
    try:
        confidence = float(confidence) if confidence is not None else 0.5
    except (TypeError, ValueError):
        confidence = 0.5
    disease_score *= 0.5 + 0.5 * max(0.0, min(1.0, confidence))

    weeds = sample.get("weeds") or {}
    try:
        coverage = float(weeds.get("weed_coverage") or 0.0)
    except (TypeError, ValueError):
        coverage = 0.0
    weed_score = max(0.0, min(1.0, coverage / _WEED_FULL_SCALE))

    return round(max(disease_score, weed_score), 4)


def _located(samples: Sequence[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int]:
    """Split the scans into ones that can be flown to, and a count that cannot."""
    located: List[Dict[str, Any]] = []
    skipped = 0
    for sample in samples or []:
        if not isinstance(sample, dict):
            continue
        lat, lon = sample.get("lat"), sample.get("lon")
        if lat is None or lon is None:
            skipped += 1
            continue
        try:
            located.append({**sample, "lat": float(lat), "lon": float(lon)})
        except (TypeError, ValueError):
            skipped += 1
    return located, skipped


def _to_metres(
    samples: List[Dict[str, Any]]
) -> Tuple[np.ndarray, float, float]:
    """Project lat/lon onto a local metre grid centred on the samples.

    A flat local projection is accurate to well under a metre over a field, and
    it is what lets K-means treat "20 m apart" the same in both axes -- raw
    degrees would stretch longitude and cluster the field into stripes.
    """
    lats = np.array([s["lat"] for s in samples], dtype=np.float64)
    lons = np.array([s["lon"] for s in samples], dtype=np.float64)
    lat0, lon0 = float(lats.mean()), float(lons.mean())

    metres_per_deg_lat = 111_320.0
    metres_per_deg_lon = 111_320.0 * max(0.05, math.cos(math.radians(lat0)))

    north = (lats - lat0) * metres_per_deg_lat
    east = (lons - lon0) * metres_per_deg_lon
    return np.column_stack([north, east]), lat0, lon0


def _kmeans(points: np.ndarray, k: int, seed: int = 42) -> np.ndarray:
    """K-means labels for ``points``, via OpenCV where available.

    Falls back to a plain Lloyd's iteration with k-means++ seeding so this
    module keeps working on a server built without the full OpenCV wheel --
    the survey summary must not fail because of an optional dependency.
    """
    try:
        import cv2

        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 60, 0.5)
        _compactness, labels, _centres = cv2.kmeans(
            points.astype(np.float32), k, None, criteria, 5,
            cv2.KMEANS_PP_CENTERS,
        )
        return labels.flatten().astype(int)
    except Exception:  # pragma: no cover - only on a cv2-less install
        return _kmeans_numpy(points, k, seed)


def _kmeans_numpy(points: np.ndarray, k: int, seed: int = 42) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = points.shape[0]

    # k-means++ seeding: a random first centre, then each further centre drawn
    # in proportion to its squared distance from the nearest chosen one.
    centres = [points[rng.integers(n)]]
    for _ in range(1, k):
        d2 = np.min(
            np.stack([np.sum((points - c) ** 2, axis=1) for c in centres]), axis=0
        )
        total = float(d2.sum())
        if total <= 0:
            centres.append(points[rng.integers(n)])
            continue
        centres.append(points[rng.choice(n, p=d2 / total)])

    centroids = np.stack(centres)
    labels = np.zeros(n, dtype=int)
    for _ in range(60):
        distances = np.stack(
            [np.sum((points - c) ** 2, axis=1) for c in centroids], axis=1
        )
        new_labels = np.argmin(distances, axis=1)
        if np.array_equal(new_labels, labels):
            break
        labels = new_labels
        for index in range(k):
            members = points[labels == index]
            if members.size:
                centroids[index] = members.mean(axis=0)
    return labels


def _severity_for(score: float) -> str:
    if score >= _SEVERE_AT:
        return "severe"
    if score >= _MODERATE_AT:
        return "moderate"
    return "healthy"


def _render_map(
    clusters: List[Dict[str, Any]],
    samples: List[Dict[str, Any]],
    path: str,
    size: int = 720,
) -> Optional[str]:
    """Draw the zone map the app shows above the spray options.

    Plotted in the local metre frame with north up, so the picture matches how
    the operator is looking at the field, with each detection as a dot coloured
    by its own score and each cluster as a circle of its sprayed radius.
    """
    try:
        import cv2
    except Exception:  # pragma: no cover
        return None
    if not samples:
        return None

    lats = [s["lat"] for s in samples]
    lons = [s["lon"] for s in samples]
    pad = 0.00012  # roughly 13 m, so edge detections are not drawn on the border
    lat_min, lat_max = min(lats) - pad, max(lats) + pad
    lon_min, lon_max = min(lons) - pad, max(lons) + pad
    lat_span = max(lat_max - lat_min, 1e-6)
    lon_span = max(lon_max - lon_min, 1e-6)

    canvas = np.full((size, size, 3), 245, dtype=np.uint8)

    def to_px(lat: float, lon: float) -> Tuple[int, int]:
        x = int((lon - lon_min) / lon_span * (size - 1))
        y = int((lat_max - lat) / lat_span * (size - 1))  # north up
        return max(0, min(size - 1, x)), max(0, min(size - 1, y))

    colours = {
        "severe": (60, 60, 220),     # BGR red
        "moderate": (60, 200, 240),  # amber
        "healthy": (80, 200, 80),    # green
    }

    metres_per_px = (lat_span * 111_320.0) / float(size)

    for cluster in clusters:
        if cluster.get("lat") is None:
            continue
        x, y = to_px(cluster["lat"], cluster["lon"])
        radius_px = max(6, int(cluster.get("radius_m", 0) / max(metres_per_px, 1e-6)))
        colour = colours.get(cluster["severity"], (150, 150, 150))
        overlay = canvas.copy()
        cv2.circle(overlay, (x, y), radius_px, colour, -1)
        cv2.addWeighted(overlay, 0.28, canvas, 0.72, 0, canvas)
        cv2.circle(canvas, (x, y), radius_px, colour, 2)

    for sample in samples:
        x, y = to_px(sample["lat"], sample["lon"])
        colour = colours.get(_severity_for(sample["_score"]), (150, 150, 150))
        cv2.circle(canvas, (x, y), 3, colour, -1)

    # Flight line, so the picture reads as a pass over a field rather than a
    # scatter of unrelated points.
    line = np.array([to_px(s["lat"], s["lon"]) for s in samples], dtype=np.int32)
    if len(line) > 1:
        cv2.polylines(canvas, [line], False, (170, 170, 170), 1)

    legend_y = 24
    for level in SEVERITY_ORDER:
        cv2.circle(canvas, (20, legend_y - 4), 6, colours[level], -1)
        cv2.putText(
            canvas, level, (34, legend_y), cv2.FONT_HERSHEY_SIMPLEX, 0.5,
            (60, 60, 60), 1, cv2.LINE_AA,
        )
        legend_y += 22

    os.makedirs(os.path.dirname(path), exist_ok=True)
    cv2.imwrite(path, canvas)
    return path


def cluster_detections(
    samples: Sequence[Dict[str, Any]],
    output_dir: Optional[str] = None,
    k: int = 3,
    swath_m: float = 3.0,
    detection_radius_m: float = DEFAULT_DETECTION_RADIUS_M,
    dose_l_per_ha: float = 20.0,
    moderate_rate: float = 0.6,
    field_area_ha: Optional[float] = None,
    crop: Optional[str] = None,
) -> Dict[str, Any]:
    """Cluster geotagged CNN detections into a flyable spray prescription.

    ``samples`` are scan results in the shape :func:`app.ai.field_scan.scan_frame`
    produces, each carrying ``lat``/``lon`` from telemetry. The return value is
    the same dict shape as :func:`app.spray.prescription.prescribe`, so the
    stored prescription, the costed options and the mission builder all work on
    it without knowing which camera the field was surveyed with.
    """
    if k < 2:
        raise HotspotError("k must be at least 2 (affected vs healthy).")
    if k > 6:
        raise HotspotError("k above 6 splits the field past what a boom can follow.")

    located, skipped_no_fix = _located(samples)
    if not located:
        raise HotspotError(
            "None of the scanned frames carried a GPS position, so there is "
            "nowhere to send the aircraft. Connect the flight link before the "
            "survey so frames are geotagged as they are scanned."
        )

    for sample in located:
        sample["_score"] = _sample_score(sample)

    points, _lat0, _lon0 = _to_metres(located)
    effective_k = min(k, len(located))

    notes: List[str] = []
    if len(located) < MIN_SAMPLES_FOR_KMEANS:
        # One patch per detection. Honest, and still flyable.
        labels = np.arange(len(located))
        effective_k = len(located)
        clustered = False
        notes.append(
            f"Only {len(located)} located detection(s) -- too few to cluster "
            "meaningfully, so each one is treated as its own patch. Fly a "
            "longer pass for a real zone map."
        )
    else:
        # Score joins the position in the feature vector, scaled so that a full
        # severity difference weighs about as much as being 30 m apart. Without
        # it K-means splits the field purely on geometry and a clean frame in
        # the middle of a sick patch gets sprayed anyway.
        score_axis = np.array([[s["_score"]] for s in located]) * 30.0
        features = np.hstack([points, score_axis])
        labels = _kmeans(features, effective_k)
        clustered = True

    clusters: List[Dict[str, Any]] = []
    for index in range(effective_k):
        members = [located[i] for i in range(len(located)) if labels[i] == index]
        if not members:
            continue

        scores = [m["_score"] for m in members]
        mean_score = float(np.mean(scores))
        severity = _severity_for(mean_score)

        lat = float(np.mean([m["lat"] for m in members]))
        lon = float(np.mean([m["lon"] for m in members]))

        # Radius: how far the member frames actually spread, plus the ground a
        # single frame covers, floored at half a swath so the aircraft is never
        # asked to spray a patch narrower than its own boom.
        member_points = points[[i for i in range(len(located)) if labels[i] == index]]
        centre = member_points.mean(axis=0)
        spread = float(np.max(np.linalg.norm(member_points - centre, axis=1))) if len(
            member_points
        ) > 1 else 0.0
        radius_m = max(spread + detection_radius_m, swath_m / 2.0)

        area_m2 = math.pi * radius_m ** 2
        conditions: Dict[str, int] = {}
        for member in members:
            name = (member.get("disease") or {}).get("name")
            if name and name != "No disease detected":
                conditions[name] = conditions.get(name, 0) + 1

        clusters.append({
            "id": len(clusters),
            "severity": severity,
            "lat": round(lat, 7),
            "lon": round(lon, 7),
            "radius_m": round(radius_m, 2),
            "area_m2": round(area_m2, 2),
            "area_ha": round(area_m2 / 10_000.0, 5),
            "frames": len(members),
            "mean_score": round(mean_score, 3),
            "max_score": round(float(max(scores)), 3),
            "mean_weed_coverage": round(
                float(np.mean([
                    float((m.get("weeds") or {}).get("weed_coverage") or 0.0)
                    for m in members
                ])), 4,
            ),
            "conditions": sorted(
                ({"name": name, "frames": count} for name, count in conditions.items()),
                key=lambda row: row["frames"], reverse=True,
            ),
            "frame_ids": [m.get("frame_id") for m in members if m.get("frame_id")][:20],
        })

    # Worst first, so a tank that runs dry runs dry on the least urgent patch.
    clusters.sort(key=lambda c: c["mean_score"], reverse=True)
    for order, cluster in enumerate(clusters):
        cluster["id"] = order

    # Only the treatable classes become patches the aircraft flies to.
    patches = [
        {
            "id": index,
            "severity": cluster["severity"],
            "lat": cluster["lat"],
            "lon": cluster["lon"],
            "radius_m": cluster["radius_m"],
            "area_m2": cluster["area_m2"],
            "area_ha": cluster["area_ha"],
            "frames": cluster["frames"],
            "conditions": cluster["conditions"],
        }
        for index, cluster in enumerate(
            c for c in clusters if c["severity"] in ("severe", "moderate")
        )
    ]

    total_area = sum(c["area_ha"] for c in clusters) or None
    areas_ha = {level: 0.0 for level in SEVERITY_ORDER}
    for cluster in clusters:
        areas_ha[cluster["severity"]] += cluster["area_ha"]

    field_ha = field_area_ha or total_area
    fractions = {
        level: round(areas_ha[level] / field_ha, 4) if field_ha else 0.0
        for level in SEVERITY_ORDER
    }

    from .prescription import _options  # local import: avoids a cycle at module load

    options = _options(
        areas_ha={k_: (v or None) for k_, v in areas_ha.items()},
        fractions=fractions,
        field_ha=field_ha,
        dose_l_per_ha=dose_l_per_ha,
        moderate_rate=moderate_rate,
    )

    spread_of_means = (
        round(max(c["mean_score"] for c in clusters)
              - min(c["mean_score"] for c in clusters), 3)
        if clusters else 0.0
    )
    low_contrast = clustered and spread_of_means < 0.15
    if low_contrast:
        notes.append(
            f"Detections across the pass are fairly uniform (score spread "
            f"{spread_of_means}). K-means will still name a worst cluster, but "
            "there may be nothing genuinely worse about it -- ground-truth "
            "before spraying."
        )
    if skipped_no_fix:
        notes.append(
            f"{skipped_no_fix} scanned frame(s) had no GPS fix and are not on "
            "the map. They still count towards the health summary."
        )
    if not patches:
        notes.append(
            "No cluster reached the moderate band, so there is nothing to "
            "target. On this evidence the block does not need a spray."
        )
    notes.append(
        "Patch outlines are inferred from where the aircraft was when each "
        "frame was scanned, not from the edge of the infection itself. Treat "
        "the radius as a spray footprint, not a diagnosis boundary."
    )

    outputs: Dict[str, Any] = {}
    if output_dir:
        rendered = _render_map(
            clusters, located, os.path.join(output_dir, "hotspot_prescription.png")
        )
        if rendered:
            outputs["prescription_map"] = rendered

    return {
        "status": "ok",
        "source": "rgb_detections",
        "index": "cnn_severity",
        "index_name": "CNN detection severity",
        "higher_is_healthier": False,
        "calibrated": False,
        "crop": crop,
        "k": effective_k,
        "clustered": clustered,
        "clusters": [
            {
                "cluster": cluster["id"],
                "severity": cluster["severity"],
                "mean_index": cluster["mean_score"],
                "pixels": cluster["frames"],
                "area_fraction": (
                    round(cluster["area_ha"] / field_ha, 4) if field_ha else 0.0
                ),
                "frames": cluster["frames"],
                "conditions": cluster["conditions"],
                "lat": cluster["lat"],
                "lon": cluster["lon"],
                "radius_m": cluster["radius_m"],
            }
            for cluster in clusters
        ],
        "cluster_spread": spread_of_means,
        "low_contrast": low_contrast,
        "severity_fractions": fractions,
        "targeted_fractions": fractions,
        "areas_ha": {level: round(value, 5) for level, value in areas_ha.items()},
        "field_ha": round(field_ha, 4) if field_ha else None,
        "patches": patches,
        "patch_count": len(patches),
        "options": options,
        "coverage": {
            "can_georeference": True,
            "method": "telemetry",
            "missing": [],
            "assumptions": [
                "Each detection is placed where the aircraft was when the "
                "frame was scanned, not where the camera was pointed.",
                "Patch radius comes from the spread of the frames in the "
                "cluster plus one frame's ground footprint.",
            ],
            "heading_deg": next(
                (s.get("heading_deg") for s in located
                 if s.get("heading_deg") is not None), 0.0,
            ),
        },
        "dose_l_per_ha": dose_l_per_ha,
        "moderate_rate": moderate_rate,
        "detections": len(located),
        "skipped_no_fix": skipped_no_fix,
        "bands_used": ["rgb"],
        "outputs": outputs,
        "notes": notes,
    }


def hotspot_geojson(prescription: Dict[str, Any]) -> Dict[str, Any]:
    """The clusters as GeoJSON, for drawing the zone map on the app's map view."""
    features = []
    for cluster in prescription.get("clusters", []):
        if cluster.get("lat") is None:
            continue
        centre = (float(cluster["lat"]), float(cluster["lon"]))
        radius = float(cluster.get("radius_m") or 0.0)
        # A circle approximated by 24 points: enough for a smooth outline at
        # field zoom, small enough to send over a field radio link.
        ring = []
        for step in range(25):
            angle = math.radians(step * (360.0 / 24.0))
            lat, lon = offset_latlon(
                centre[0], centre[1],
                radius * math.cos(angle), radius * math.sin(angle),
            )
            ring.append([round(lon, 7), round(lat, 7)])
        features.append({
            "type": "Feature",
            "geometry": {"type": "Polygon", "coordinates": [ring]},
            "properties": {
                "cluster": cluster.get("cluster"),
                "severity": cluster.get("severity"),
                "frames": cluster.get("frames"),
                "radius_m": radius,
                "conditions": cluster.get("conditions", []),
            },
        })
    return {"type": "FeatureCollection", "features": features}
