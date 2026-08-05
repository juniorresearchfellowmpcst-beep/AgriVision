"""Tests for the K-means spray prescription and the spray mission it becomes.

The two things that must not silently break:

  * the clustering has to put the *stressed* part of the field in the severe
    class and cost it honestly — a prescription that mislabels the zones sends
    chemical onto healthy crop and leaves the sick patch untreated;
  * the mission has to open the valve over the patch and close it again — the
    saving only exists if the pump actually follows the plan.

Synthetic captures throughout: a field with a known bad corner, so the expected
answer is arithmetic rather than agronomy.
"""

import os

import cv2
import numpy as np
import pytest

from app.spray.geo import Georeferencer, ground_sample_distance, pixel_to_latlon
from app.spray.mission import (
    CMD_DO_SET_SERVO,
    CMD_DO_SPRAYER,
    build_spray_mission,
    patch_passes,
    pump_commands,
)
from app.spray.prescription import PrescriptionError, patches_for_levels, prescribe

# A field 300x300 px with three known regions, written as red + NIR bands.
#   healthy  : NDVI ~ 0.74
#   moderate : NDVI ~ 0.33
#   severe   : NDVI ~ 0.05
SIZE = 300


def _write_bands(directory):
    red = np.full((SIZE, SIZE), 30, dtype=np.uint8)
    nir = np.full((SIZE, SIZE), 200, dtype=np.uint8)

    # Severe block, top-left quarter-ish.
    red[20:100, 20:100] = 55
    nir[20:100, 20:100] = 62

    # Moderate block, bottom-right.
    red[190:260, 190:260] = 60
    nir[190:260, 190:260] = 120

    paths = {}
    for name, band in (("red", red), ("nir", nir)):
        path = os.path.join(directory, f"{name}.png")
        cv2.imwrite(path, band)
        paths[name] = path
    return paths


@pytest.fixture
def capture(tmp_path):
    directory = tmp_path / "capture"
    directory.mkdir()
    return _write_bands(str(directory))


# ── geo ──────────────────────────────────────────────────────────────────

def test_gsd_scales_with_altitude():
    low = ground_sample_distance(alt_m=10, fov_deg=60, image_width_px=1000)
    high = ground_sample_distance(alt_m=20, fov_deg=60, image_width_px=1000)
    assert high == pytest.approx(low * 2)


def test_gsd_refuses_impossible_inputs():
    assert ground_sample_distance(0, 60, 1000) is None
    assert ground_sample_distance(10, 0, 1000) is None
    assert ground_sample_distance(10, 60, 0) is None


def test_pixel_above_centre_is_ahead_of_the_aircraft():
    """Image y grows downward; a pixel above centre must map north when the
    aircraft is heading north. Getting this backwards mirrors the whole
    prescription front-to-back."""
    lat, lon = pixel_to_latlon(
        px=500, py=100, image_size=(1000, 1000),
        center_lat=23.2, center_lon=77.4, gsd_m=0.1, heading_deg=0,
    )
    assert lat > 23.2
    assert lon == pytest.approx(77.4, abs=1e-9)


def test_heading_rotates_the_offset():
    """Flying east, the same pixel must map east instead of north."""
    lat, lon = pixel_to_latlon(
        px=500, py=100, image_size=(1000, 1000),
        center_lat=23.2, center_lon=77.4, gsd_m=0.1, heading_deg=90,
    )
    assert lon > 77.4
    assert lat == pytest.approx(23.2, abs=1e-6)


def test_georeferencer_reports_what_is_missing():
    referencer = Georeferencer((640, 480), lat=None, lon=None, alt_m=None, fov_deg=None)
    assert not referencer.can_georeference
    described = referencer.describe()
    assert described["georeferenced"] is False
    assert described["missing"]


# ── prescription ─────────────────────────────────────────────────────────

def test_kmeans_finds_the_stressed_zones(capture, tmp_path):
    result = prescribe(capture, output_dir=str(tmp_path / "out"), k=3)

    assert result["status"] == "ok"
    assert result["index"] == "ndvi"

    clusters = {c["severity"]: c for c in result["clusters"]}
    assert set(clusters) == {"severe", "moderate", "healthy"}
    # Severity must track vigor: severe is the lowest-index cluster.
    assert clusters["severe"]["mean_index"] < clusters["moderate"]["mean_index"]
    assert clusters["moderate"]["mean_index"] < clusters["healthy"]["mean_index"]

    # Most of the synthetic field is healthy, and the bad blocks are found.
    fractions = result["severity_fractions"]
    assert fractions["healthy"] > 0.7
    assert fractions["severe"] > 0.03
    assert fractions["moderate"] > 0.02


def test_options_quantify_the_saving(capture, tmp_path):
    result = prescribe(capture, output_dir=str(tmp_path / "out"), k=3)
    options = {o["id"]: o for o in result["options"]}

    assert set(options) == {"severe_only", "severe_moderate", "blanket"}
    # Targeting must save chemical against a blanket pass, and treating more
    # of the field must save less than treating less of it.
    assert options["severe_only"]["saving_percent"] > 50
    assert options["blanket"]["saving_percent"] == 0
    assert (
        options["severe_only"]["saving_percent"]
        >= options["severe_moderate"]["saving_percent"]
    )
    assert exactly_one_recommendation(result["options"])


def exactly_one_recommendation(options):
    return sum(1 for option in options if option["recommended"]) == 1


def test_patches_get_coordinates_when_the_capture_is_georeferenced(capture, tmp_path):
    result = prescribe(
        capture, output_dir=str(tmp_path / "out"), k=3,
        lat=23.2599, lon=77.4126, alt_m=30.0, fov_deg=62.0, heading_deg=0.0,
    )

    assert result["coverage"]["georeferenced"] is True
    assert result["patches"], "the stressed blocks should survive cleanup as patches"
    for patch in result["patches"]:
        assert "lat" in patch and "lon" in patch
        assert patch["area_ha"] is not None
        assert patch["radius_m"] > 0
    # Field area is measured from the footprint, so it must be a real number.
    assert result["field_ha"] > 0


def test_without_a_fix_the_prescription_still_renders_but_says_why(capture, tmp_path):
    result = prescribe(capture, output_dir=str(tmp_path / "out"), k=3)

    assert result["coverage"]["georeferenced"] is False
    assert any("waypoints" in note for note in result["notes"])
    # A patch with no coordinates must not pretend to have one.
    assert all("lat" not in patch for patch in result["patches"])


def test_uniform_field_is_flagged_low_contrast(tmp_path):
    directory = tmp_path / "flat"
    directory.mkdir()
    # A healthy field with only sensor-level noise: K-means will still name a
    # worst cluster, and the caller must be told not to trust it.
    rng = np.random.default_rng(7)
    red = np.clip(rng.normal(30, 1.5, (SIZE, SIZE)), 0, 255).astype(np.uint8)
    nir = np.clip(rng.normal(200, 1.5, (SIZE, SIZE)), 0, 255).astype(np.uint8)
    paths = {}
    for name, band in (("red", red), ("nir", nir)):
        path = str(directory / f"{name}.png")
        cv2.imwrite(path, band)
        paths[name] = path

    result = prescribe(paths, output_dir=str(tmp_path / "out"), k=3)
    assert result["low_contrast"] is True
    assert any("uniform" in note for note in result["notes"])


def test_prescription_writes_a_map(capture, tmp_path):
    out = tmp_path / "out"
    result = prescribe(capture, output_dir=str(out), k=3)
    map_path = result["outputs"]["prescription_map"]
    assert os.path.isfile(map_path)
    assert cv2.imread(map_path) is not None


def test_rejects_a_capture_with_no_usable_bands(tmp_path):
    directory = tmp_path / "green_only"
    directory.mkdir()
    path = str(directory / "green.png")
    cv2.imwrite(path, np.full((64, 64), 120, dtype=np.uint8))

    with pytest.raises(PrescriptionError, match="red \\+ NIR"):
        prescribe({"green": path}, output_dir=str(tmp_path / "out"))


def test_k_is_bounded(capture, tmp_path):
    with pytest.raises(PrescriptionError):
        prescribe(capture, output_dir=str(tmp_path / "out"), k=1)
    with pytest.raises(PrescriptionError):
        prescribe(capture, output_dir=str(tmp_path / "out"), k=9)


# ── mission ──────────────────────────────────────────────────────────────

def test_small_patch_still_gets_an_entry_and_an_exit():
    """One waypoint would open the valve without the aircraft ever moving."""
    points = patch_passes(23.2, 77.4, radius_m=0.5, swath_m=3.0)
    assert len(points) == 2
    assert points[0] != points[1]


def test_large_patch_gets_multiple_passes():
    small = patch_passes(23.2, 77.4, radius_m=2.0, swath_m=3.0)
    large = patch_passes(23.2, 77.4, radius_m=12.0, swath_m=3.0)
    assert len(large) > len(small)
    assert len(large) % 2 == 0  # every pass line has two ends


def test_spray_mission_brackets_each_patch_with_valve_commands():
    targets = [
        {"lat": 23.2, "lon": 77.4, "radius_m": 6.0, "severity": "severe"},
        {"lat": 23.2005, "lon": 77.4005, "radius_m": 4.0, "severity": "moderate"},
    ]
    built = build_spray_mission(targets, altitude_m=3.0, speed_ms=3.0)
    commands = [item["command"] for item in built["items"]]

    # One OFF before the run starts, then ON/OFF per patch.
    assert commands.count(CMD_DO_SPRAYER) == 1 + 2 * len(targets)
    on_commands = [
        item for item in built["items"]
        if item["command"] == CMD_DO_SPRAYER and item["param1"] == 1.0
    ]
    assert len(on_commands) == len(targets)

    summary = built["summary"]
    assert summary["patches"] == 2
    assert summary["has_rtl"] is True
    assert summary["path_length_m"] > 0


def test_mission_starts_with_the_valve_shut():
    """A pump left open by a previous flight would spray the whole transit."""
    built = build_spray_mission(
        [{"lat": 23.2, "lon": 77.4, "radius_m": 5.0, "severity": "severe"}]
    )
    valve_items = [i for i in built["items"] if i["command"] == CMD_DO_SPRAYER]
    assert valve_items[0]["param1"] == 0.0


def test_servo_rig_flies_a_reduced_rate_over_moderate_zones():
    config = {
        "mechanism": "servo", "servo_channel": 9,
        "servo_off_pwm": 1000, "servo_on_pwm": 2000, "relay_number": 0,
        "swath_m": 3.0, "spray_altitude_m": 3.0, "spray_speed_ms": 3.0,
        "variable_rate": True,
    }
    built = build_spray_mission(
        [
            {"lat": 23.2, "lon": 77.4, "radius_m": 5.0, "severity": "severe"},
            {"lat": 23.201, "lon": 77.401, "radius_m": 5.0, "severity": "moderate"},
        ],
        config=config,
        moderate_rate=0.6,
    )
    pwms = sorted(
        item["param2"] for item in built["items"]
        if item["command"] == CMD_DO_SET_SERVO and item["param2"] > 1000
    )
    # Severe fully open, moderate 60% of the way.
    assert pwms == [1600.0, 2000.0]


def test_on_off_rig_does_not_pretend_to_vary_the_rate():
    """DO_SPRAYER has no rate argument, so a 'reduced' moderate dose would be
    a saving quoted to the farmer that the hardware cannot deliver."""
    built = build_spray_mission(
        [{"lat": 23.2, "lon": 77.4, "radius_m": 5.0, "severity": "moderate"}],
        moderate_rate=0.6,
    )
    on_items = [
        i for i in built["items"]
        if i["command"] == CMD_DO_SPRAYER and i["param1"] == 1.0
    ]
    assert on_items and all(item["param1"] == 1.0 for item in on_items)


def test_mission_refuses_targets_without_coordinates():
    with pytest.raises(ValueError, match="nothing to fly"):
        build_spray_mission([{"severity": "severe", "radius_m": 4.0}])


def test_relay_rig_switches_the_pump():
    config = dict(
        mechanism="relay", servo_channel=9, servo_off_pwm=1000, servo_on_pwm=2000,
        relay_number=2, swath_m=3.0, spray_altitude_m=3.0, spray_speed_ms=3.0,
        variable_rate=False,
    )
    on = pump_commands(True, 1.0, config)[0]
    assert on["param1"] == 2.0 and on["param2"] == 1.0


def test_patches_for_levels_filters_by_severity():
    prescription = {
        "patches": [
            {"id": 0, "severity": "severe"},
            {"id": 1, "severity": "moderate"},
            {"id": 2, "severity": "moderate"},
        ]
    }
    assert len(patches_for_levels(prescription, ["severe"])) == 1
    assert len(patches_for_levels(prescription, ["severe", "moderate"])) == 3
    assert patches_for_levels(prescription, []) == []
