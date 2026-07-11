"""End-to-end tests for the multispectral preprocessing + mission modules.

Builds synthetic 5-band imagery with a known calibration panel and known
vegetation gradient, then checks that:
  * reflectance calibration recovers the reflectance we baked in,
  * band alignment improves the alignment score and flags it clean,
  * NDVI/GNDVI/NDRE come out in range,
  * K-means splits the field into ordered low/medium/high zones,
  * KML parsing + mission planning produce ordered waypoints.
"""

import os

import cv2
import numpy as np
import pytest

from app.preprocessing import PipelineConfig, preprocess_capture
from app.mission import build_mission, parse_kml


BANDS = ["blue", "green", "red", "red_edge", "nir"]
PANEL_DN = {"blue": 30000, "green": 32000, "red": 31000, "red_edge": 33000, "nir": 34000}
PANEL_REFLECTANCE = 0.5
H, W = 120, 180


def _vigor_map():
    """Field with three vertical vigor bands (low/med/high) plus texture."""
    v = np.zeros((H, W), np.float32)
    v[:, : W // 3] = 0.2
    v[:, W // 3 : 2 * W // 3] = 0.5
    v[:, 2 * W // 3 :] = 0.8
    # Structural features so alignment has edges to lock onto.
    cv2.circle(v, (40, 30), 12, 0.9, -1)
    cv2.circle(v, (140, 90), 14, 0.1, -1)
    cv2.rectangle(v, (80, 20), (110, 100), 0.6, 3)
    return np.clip(v, 0.02, 0.98)


def _reflectance_bands(vigor):
    """Physically-plausible per-band reflectance from a vigor map."""
    nir = 0.20 + 0.60 * vigor
    red = 0.30 - 0.18 * vigor
    return {
        "blue": 0.10 + 0.05 * vigor,
        "green": 0.15 + 0.10 * vigor,
        "red": red,
        "red_edge": 0.25 + 0.20 * vigor,
        "nir": nir,
    }


def _make_capture(tmp_path):
    """Write synthetic panel + scene band files; return their paths."""
    vigor = _vigor_map()
    refl = _reflectance_bands(vigor)

    scene_dir = tmp_path / "scene"
    panel_dir = tmp_path / "panel"
    scene_dir.mkdir()
    panel_dir.mkdir()

    band_paths, panel_paths = {}, {}
    for i, band in enumerate(BANDS):
        # Scene raw DN inverts calibration so we can recover reflectance exactly:
        # DN = reflectance * panel_DN / panel_reflectance.
        dn = (refl[band] * PANEL_DN[band] / PANEL_REFLECTANCE).astype(np.float32)
        # Apply a known 2-3px shift to every band except the reference (green).
        if band != "green":
            shift = np.float32([[1, 0, (i + 1)], [0, 1, -(i + 1)]])
            dn = cv2.warpAffine(dn, shift, (W, H), borderMode=cv2.BORDER_REFLECT)
        sp = scene_dir / f"{band}.tif"
        cv2.imwrite(str(sp), dn.astype(np.uint16))
        band_paths[band] = str(sp)

        # Panel photo: uniform bright block on a darker textured background.
        panel = np.random.RandomState(i).randint(3000, 6000, (H, W)).astype(np.uint16)
        panel[30:90, 60:120] = PANEL_DN[band]
        pp = panel_dir / f"{band}.tif"
        cv2.imwrite(str(pp), panel)
        panel_paths[band] = str(pp)

    return band_paths, panel_paths


def test_full_pipeline(tmp_path):
    band_paths, panel_paths = _make_capture(tmp_path)

    config = PipelineConfig()
    config.panel.reflectance = {b: PANEL_REFLECTANCE for b in BANDS}
    # Explicit panel ROI (matches the bright block) for a deterministic test.
    config.panel.roi = {"all": (60, 30, 60, 60)}
    # Distortion is pure translation, so use the translation warp model.
    config.alignment.warp_mode = "translation"

    report = preprocess_capture(
        band_paths=band_paths,
        panel_paths=panel_paths,
        output_dir=str(tmp_path / "out"),
        config=config,
        indices=["ndvi", "gndvi", "ndre"],
        zones=3,
        zone_index="ndvi",
    )

    assert report["status"] == "ok"

    # --- Reflectance calibration recovers the baked-in reflectance scale. ---
    for band in BANDS:
        expected_scale = PANEL_REFLECTANCE / PANEL_DN[band]
        got = report["reflectance_scale"][band]["scale"]
        assert got == pytest.approx(expected_scale, rel=0.05)

    # --- Band alignment: bands line up cleanly, scores improved. ---
    align = report["alignment"]
    assert align["aligned_cleanly"] is True
    assert align["mean_score"] > 0.65
    for band in BANDS:
        if band == "green":
            continue
        pb = align["per_band"][band]
        assert pb["score_after"] >= pb["score_before"] - 0.02

    # --- Indices present and in physical range. ---
    for idx in ("ndvi", "gndvi", "ndre"):
        stats = report["indices"][idx]["stats"]
        assert -1.0 <= stats["min"] <= stats["max"] <= 1.0
        assert stats["count"] > 0

    # --- K-means zones ordered low -> medium -> high. ---
    zones = report["zones"]
    assert zones["k"] == 3
    labels = [z["label"] for z in zones["zones"]]
    assert labels == ["low", "medium", "high"]
    centers = [z["center_index"] for z in zones["zones"]]
    assert centers == sorted(centers)  # strictly ordered by vigor
    assert sum(z["area_fraction"] for z in zones["zones"]) == pytest.approx(1.0, abs=0.02)

    # --- Output files written. ---
    assert os.path.isfile(report["outputs"]["preview"])
    assert os.path.isfile(report["indices"]["ndvi"]["preview"])


def test_kml_path_mission():
    kml = """<?xml version="1.0" encoding="UTF-8"?>
    <kml xmlns="http://www.opengis.net/kml/2.2"><Document>
      <Placemark><name>route</name><LineString><coordinates>
        77.1000,28.7000,0 77.1010,28.7000,0 77.1010,28.7010,0
      </coordinates></LineString></Placemark>
    </Document></kml>"""
    parsed = parse_kml(kml)
    assert parsed["counts"]["path"] == 1

    mission = build_mission(parsed, altitude_m=50.0)
    assert mission["source"] == "explicit-path"
    assert mission["waypoint_count"] == 3
    assert all(wp["alt"] == 50.0 for wp in mission["waypoints"])
    assert mission["distance_m"] > 0


def test_kml_polygon_survey():
    # ~100m square field boundary.
    kml = """<?xml version="1.0" encoding="UTF-8"?>
    <kml xmlns="http://www.opengis.net/kml/2.2"><Document>
      <Placemark><name>field</name><Polygon><outerBoundaryIs><LinearRing>
        <coordinates>
          77.1000,28.7000,0 77.1010,28.7000,0 77.1010,28.7009,0
          77.1000,28.7009,0 77.1000,28.7000,0
        </coordinates>
      </LinearRing></outerBoundaryIs></Polygon></Placemark>
    </Document></kml>"""
    parsed = parse_kml(kml)
    assert parsed["counts"]["polygon"] == 1

    mission = build_mission(parsed, altitude_m=60.0, line_spacing_m=20.0)
    assert mission["source"] == "polygon-survey"
    assert mission["waypoint_count"] >= 4          # several survey lines
    assert mission["distance_m"] > 0


def test_kml_invalid_raises():
    with pytest.raises(ValueError):
        parse_kml("not xml at all")


# ── Index registry + risk + report ──────────────────────────────────────────

def test_index_registry():
    from app.preprocessing import list_indices, available_indices

    catalog = list_indices()
    assert len(catalog) >= 15
    keys = {c["key"] for c in catalog}
    assert {"ndvi", "gndvi", "ndre", "savi", "evi", "gci", "reci", "ndwi"} <= keys
    # RGB-only capture still yields visible-band indices.
    rgb = available_indices(["red", "green", "blue"])
    assert "grvi" in rgb and "vari" in rgb
    assert "ndvi" not in rgb  # needs NIR


def test_analyze_images_uncalibrated(tmp_path):
    from app.preprocessing import analyze_images

    band_paths, _ = _make_capture(tmp_path)
    result = analyze_images(band_paths=band_paths, output_dir=str(tmp_path / "an"))

    assert result["status"] == "ok"
    assert result["calibrated"] is False
    # Shared-scale pseudo-reflectance keeps NDVI physically sensible.
    assert 0.2 < result["indices"]["ndvi"]["stats"]["mean"] < 0.8
    # Risk distribution covers the three vigor bands and sums to ~1.
    dist = result["risk"]["distribution"]
    assert set(dist) == {"high", "medium", "low"}
    assert sum(dist.values()) == pytest.approx(1.0, abs=0.05)
    # Report + action plan present and non-trivial.
    assert result["report"]["health_score"] is not None
    assert len(result["action_plan"]) >= 2
    assert all("title" in a and "priority" in a for a in result["action_plan"])
    assert os.path.isfile(result["outputs"]["risk_map"])


def test_analyze_images_endpoint(tmp_path):
    """Full HTTP path: multipart upload -> report JSON + fetchable preview URL."""
    import io as _io
    import cv2

    from app import create_app

    band_paths, _ = _make_capture(tmp_path)
    app = create_app()
    app.instance_path = str(tmp_path / "instance")
    client = app.test_client()

    # Post the band files as multipart, named so auto-detect finds each band.
    data = {}
    for band, path in band_paths.items():
        with open(path, "rb") as fh:
            data[band] = (_io.BytesIO(fh.read()), f"{band}.tif")

    resp = client.post("/api/preprocessing/analyze-images", data=data,
                       content_type="multipart/form-data")
    assert resp.status_code == 200, resp.get_data(as_text=True)
    body = resp.get_json()
    assert body["status"] == "ok"
    assert body["primary_index"] == "ndvi"
    assert "job_id" in body

    # The risk-map URL should be fetchable through the output route.
    risk_url = body["outputs"]["risk_map"]
    assert "/api/preprocessing/output/" in risk_url
    rel = risk_url.split("/api/preprocessing/output/")[1]
    img_resp = client.get(f"/api/preprocessing/output/{rel}")
    assert img_resp.status_code == 200
    assert img_resp.data[:4] == b"\x89PNG"


def test_analyze_images_endpoint_band_map(tmp_path):
    """Files with no band keyword in their name resolve via explicit band_map."""
    import io as _io
    import json as _json

    from app import create_app

    band_paths, _ = _make_capture(tmp_path)
    app = create_app()
    app.instance_path = str(tmp_path / "instance")
    client = app.test_client()

    # Upload under generic names that auto-detect could NOT resolve.
    data = {}
    band_map = {}
    for i, (band, path) in enumerate(band_paths.items()):
        fname = f"capture_{i}.tif"
        with open(path, "rb") as fh:
            data[f"img{i}"] = (_io.BytesIO(fh.read()), fname)
        band_map[band] = fname
    data["band_map"] = _json.dumps(band_map)

    resp = client.post("/api/preprocessing/analyze-images", data=data,
                       content_type="multipart/form-data")
    assert resp.status_code == 200, resp.get_data(as_text=True)
    body = resp.get_json()
    assert body["status"] == "ok"
    # All five bands were resolved from the explicit map, so NDVI is available.
    assert set(body["bands_used"]) == {"blue", "green", "red", "red_edge", "nir"}
    assert body["primary_index"] == "ndvi"
