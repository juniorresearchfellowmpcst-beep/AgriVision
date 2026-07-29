"""Tests for the MAVLink integration that need no vehicle on the wire.

Covers the two halves that can go wrong silently:
  * mission translation — the waypoint list the app sends becomes a *flyable*
    item list (home, takeoff, survey legs, RTL) with sane frames and altitudes,
  * the HTTP surface — status is always answerable, a plan can be validated
    with dry_run, and anything needing a vehicle fails with a readable message
    instead of a stack trace.

The live protocol (upload handshake, arm/AUTO/start, RTL) is exercised against
a simulator; see docs/MAVLINK_SITL.md for that flow.
"""

import pytest

from app import create_app
from app.mavlink import link, normalise_waypoints, summarise
from app.mavlink.mission_items import (
    CMD_DO_CHANGE_SPEED,
    CMD_NAV_RETURN_TO_LAUNCH,
    CMD_NAV_TAKEOFF,
    CMD_NAV_WAYPOINT,
    FRAME_GLOBAL,
    FRAME_GLOBAL_RELATIVE_ALT,
    build_mission_items,
)

BLOCK = [
    {"lat": 23.19180, "lon": 77.42020},
    {"lat": 23.19200, "lon": 77.42074},
    {"lat": 23.19200, "lon": 77.42193},
    {"lat": 23.19125, "lon": 77.42247},
]


# ── waypoint normalisation ────────────────────────────────────────────────


def test_normalise_accepts_the_shapes_the_app_sends():
    cleaned = normalise_waypoints(
        [
            {"lat": 23.1, "lon": 77.4},           # planner / saved mission
            {"latitude": 23.2, "longitude": 77.5},  # verbose form
            {"lat": 23.3, "lng": 77.6},            # leaflet-style
            [23.4, 77.7],                          # bare pair
        ],
        default_alt_m=30.0,
    )
    assert [w["lat"] for w in cleaned] == [23.1, 23.2, 23.3, 23.4]
    assert all(w["alt"] == 30.0 for w in cleaned)


def test_normalise_drops_unusable_points():
    cleaned = normalise_waypoints(
        [
            {"lat": "not-a-number", "lon": 77.4},
            {"lat": 91.0, "lon": 77.4},   # out of range
            {"lon": 77.4},                 # missing lat
            None,
            {"lat": 23.1, "lon": 77.4},    # the only good one
        ],
        default_alt_m=30.0,
    )
    assert len(cleaned) == 1
    assert cleaned[0]["lat"] == 23.1


def test_normalise_replaces_zero_altitude_with_the_flight_altitude():
    # The KML planner writes alt 0 for 2-D boundaries; flying that is a crash.
    cleaned = normalise_waypoints([{"lat": 23.1, "lon": 77.4, "alt": 0}], 45.0)
    assert cleaned[0]["alt"] == 45.0


# ── mission translation ───────────────────────────────────────────────────


def test_mission_has_home_takeoff_survey_and_rtl_in_order():
    items = build_mission_items(normalise_waypoints(BLOCK, 30.0), altitude_m=30.0)

    assert items[0]["command"] == CMD_NAV_WAYPOINT
    assert items[0]["frame"] == FRAME_GLOBAL      # home is MSL-framed
    assert items[0]["current"] == 1               # only seq 0 is 'current'
    assert items[1]["command"] == CMD_NAV_TAKEOFF
    assert items[1]["alt"] == 30.0
    assert items[-1]["command"] == CMD_NAV_RETURN_TO_LAUNCH

    assert [i["seq"] for i in items] == list(range(len(items)))
    assert all(i["autocontinue"] == 1 for i in items)

    survey = [i for i in items[2:-1]]
    assert len(survey) == len(BLOCK)
    assert all(i["frame"] == FRAME_GLOBAL_RELATIVE_ALT for i in survey)
    assert all(i["alt"] == 30.0 for i in survey)


def test_speed_is_only_commanded_when_asked_for():
    without = build_mission_items(normalise_waypoints(BLOCK, 30.0), altitude_m=30.0)
    assert not any(i["command"] == CMD_DO_CHANGE_SPEED for i in without)

    with_speed = build_mission_items(
        normalise_waypoints(BLOCK, 30.0), altitude_m=30.0, speed_ms=7.0
    )
    change = next(i for i in with_speed if i["command"] == CMD_DO_CHANGE_SPEED)
    assert change["param1"] == 1.0    # ground speed
    assert change["param2"] == 7.0
    assert change["param3"] == -1.0   # leave throttle alone


def test_home_defaults_to_the_first_waypoint_without_a_gps_fix():
    items = build_mission_items(normalise_waypoints(BLOCK, 30.0), altitude_m=30.0)
    assert items[0]["lat"] == pytest.approx(BLOCK[0]["lat"])
    assert items[0]["lon"] == pytest.approx(BLOCK[0]["lon"])


def test_home_uses_the_vehicle_position_when_known():
    items = build_mission_items(
        normalise_waypoints(BLOCK, 30.0),
        altitude_m=30.0,
        home_lat=23.0,
        home_lon=77.0,
    )
    assert (items[0]["lat"], items[0]["lon"]) == (23.0, 77.0)
    assert (items[1]["lat"], items[1]["lon"]) == (23.0, 77.0)  # takeoff at home


def test_rtl_can_be_left_off():
    items = build_mission_items(
        normalise_waypoints(BLOCK, 30.0), altitude_m=30.0, return_to_launch=False
    )
    assert not any(i["command"] == CMD_NAV_RETURN_TO_LAUNCH for i in items)


@pytest.mark.parametrize("altitude", [0, -5])
def test_non_positive_altitude_is_rejected(altitude):
    with pytest.raises(ValueError):
        build_mission_items(normalise_waypoints(BLOCK, 30.0), altitude_m=altitude)


def test_empty_waypoints_are_rejected():
    with pytest.raises(ValueError):
        build_mission_items([], altitude_m=30.0)


def test_summarise_counts_only_survey_waypoints():
    items = build_mission_items(normalise_waypoints(BLOCK, 30.0), altitude_m=30.0)
    assert summarise(items) == {
        "item_count": len(items),
        "nav_waypoints": len(BLOCK),
        "has_takeoff": True,
        "has_rtl": True,
    }


# ── HTTP surface ──────────────────────────────────────────────────────────


@pytest.fixture
def client():
    app = create_app()
    app.config.update(TESTING=True)
    with app.test_client() as c:
        yield c


def test_status_answers_with_no_vehicle_connected(client):
    body = client.get("/api/mavlink/status").get_json()
    assert body["status"] == "ok"
    assert body["connected"] is False
    assert body["alive"] is False
    assert "telemetry" in body


def test_dry_run_validates_a_plan_without_a_vehicle(client):
    response = client.post(
        "/api/mavlink/mission",
        json={"waypoints": BLOCK, "altitude_m": 25, "dry_run": True},
    )
    body = response.get_json()
    assert response.status_code == 200
    assert body["dry_run"] is True
    assert body["summary"]["nav_waypoints"] == len(BLOCK)
    assert all(i["alt"] in (0.0, 25.0) for i in body["items"])


def test_upload_without_waypoints_explains_what_to_send(client):
    response = client.post("/api/mavlink/mission", json={"waypoints": []})
    assert response.status_code == 400
    assert "waypoints" in response.get_json()["message"]


def test_upload_without_a_link_fails_readably(client):
    assert not link.is_connected  # nothing connected in a unit-test run
    response = client.post("/api/mavlink/mission", json={"waypoints": BLOCK})
    assert response.status_code == 502
    assert "connect" in response.get_json()["message"].lower()


def test_flight_control_requires_a_login(client):
    for path in ("/api/mavlink/connect", "/api/mavlink/start", "/api/mavlink/command"):
        assert client.post(path, json={"action": "rtl"}).status_code == 401
