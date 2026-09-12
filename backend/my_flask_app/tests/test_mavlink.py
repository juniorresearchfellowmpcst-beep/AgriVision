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

import time
from unittest.mock import MagicMock, patch

import pytest
from flask_jwt_extended import create_access_token

from app import create_app
from app.mavlink import MavlinkError, link, normalise_waypoints, summarise
from app.mavlink.link import MavlinkLink, is_vehicle_heartbeat
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


# ── launch sequence ───────────────────────────────────────────────────────


def _recording_link(armed=False, modes=("GUIDED", "AUTO", "LOITER", "STABILIZE")):
    """A link with a fake vehicle attached, recording the calls it makes."""
    instance = MavlinkLink()
    master = MagicMock()
    master.mode_mapping.return_value = {name: i for i, name in enumerate(modes)}
    instance._master = master
    instance._telemetry["armed"] = armed
    # A vehicle that is talking, with the fix a launch needs. These tests are
    # about the *order* of the launch steps; the pre-flight gate that reads
    # these fields has its own tests below.
    instance._last_heartbeat = time.time()
    instance._telemetry["gps_fix"] = 3
    instance._telemetry["satellites"] = 12

    calls = []
    patches = [
        patch.object(
            instance, "set_mode",
            side_effect=lambda mode, **kw: calls.append(f"mode:{mode}") or {},
        ),
        patch.object(
            instance, "arm",
            side_effect=lambda **kw: calls.append("arm") or {},
        ),
        patch.object(
            instance, "send_command_long",
            side_effect=lambda *a, **kw: calls.append("mission_start") or {},
        ),
    ]
    return instance, calls, patches


def test_launch_arms_before_switching_to_auto():
    """ArduCopter answers "Arm: Auto mode not armable", so setting AUTO first
    and then arming leaves the aircraft sitting on the ground with a valid
    flight plan loaded — which is exactly what it looks like when this
    regresses. Arm from GUIDED, then hand over."""
    instance, calls, patches = _recording_link(armed=False)

    for p in patches:
        p.start()
    try:
        instance.start_mission()
    finally:
        for p in patches:
            p.stop()

    assert calls == ["mode:GUIDED", "arm", "mode:AUTO", "mission_start"]


def test_launch_of_an_armed_vehicle_skips_the_arming_mode():
    """A copter already in the air must not be dropped into GUIDED on its way
    to AUTO — that would interrupt the flight it is already doing."""
    instance, calls, patches = _recording_link(armed=True)

    for p in patches:
        p.start()
    try:
        instance.start_mission()
    finally:
        for p in patches:
            p.stop()

    assert calls == ["mode:AUTO", "mission_start"]


def test_launch_falls_back_when_guided_is_unavailable():
    instance, calls, patches = _recording_link(
        armed=False, modes=("AUTO", "LOITER", "STABILIZE")
    )

    for p in patches:
        p.start()
    try:
        instance.start_mission()
    finally:
        for p in patches:
            p.stop()

    assert calls[0] == "mode:LOITER"
    assert calls[1] == "arm"


def test_launch_reports_when_there_is_no_armable_mode():
    from app.mavlink import MavlinkError

    instance, _calls, patches = _recording_link(armed=False, modes=("AUTO",))

    for p in patches:
        p.start()
    try:
        with pytest.raises(MavlinkError, match="to arm from"):
            instance.start_mission()
    finally:
        for p in patches:
            p.stop()


# ── HTTP surface ──────────────────────────────────────────────────────────


@pytest.fixture
def client():
    app = create_app({
        "TESTING": True,
        # Isolated from the developer's real database. This MUST go through
        # create_app: overriding the config afterwards leaves the engine bound
        # to the dev database, and drop_all() then deletes real data.
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret",
    })
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


def test_preflight_answers_with_no_vehicle_connected(client):
    body = client.get("/api/mavlink/preflight").get_json()
    assert body["ready"] is False
    assert any("connected" in problem.lower() for problem in body["problems"])


@pytest.fixture
def auth(client):
    """Authorization header for a signed-in operator."""
    with client.application.app_context():
        return {"Authorization": f"Bearer {create_access_token(identity='1')}"}


@pytest.fixture
def armed_vehicle():
    """The process-wide link, standing in for an aircraft that is flying."""
    link._master = MagicMock()
    link._last_heartbeat = time.time()
    link._target_system, link._target_component = 1, 1
    link._telemetry["armed"] = True
    yield link
    link.disconnect()


def test_the_link_is_not_closed_under_a_flying_drone(client, auth, armed_vehicle):
    """Closing the link takes away the telemetry and the app's Return Home and
    Land buttons, and the autopilot may fall back to its own failsafe. It is
    still allowed for someone who insists."""
    refused = client.post("/api/mavlink/disconnect", json={}, headers=auth)
    assert refused.status_code == 409
    assert "armed" in refused.get_json()["message"]

    forced = client.post(
        "/api/mavlink/disconnect", json={"force": True}, headers=auth
    )
    assert forced.status_code == 200
    assert forced.get_json()["connected"] is False


def test_return_home_shuts_the_spray_valve_first(
    client, auth, armed_vehicle, monkeypatch
):
    """A change of flight mode does not close a valve. An aircraft sent home
    from the middle of a patch would spray its way back across the field."""
    order = []
    armed_vehicle._mission_kind = "spray"
    monkeypatch.setattr(
        armed_vehicle, "send_command_long",
        lambda *a, **kw: order.append(kw.get("label", "command")) or {},
    )
    monkeypatch.setattr(
        armed_vehicle, "set_mode",
        lambda mode, **kw: order.append(f"mode:{mode}") or {},
    )

    response = client.post(
        "/api/mavlink/command", json={"action": "rtl"}, headers=auth
    )
    assert response.status_code == 200, response.get_json()
    assert order[-1] == "mode:RTL"
    assert order[:-1], "the valve must be closed before the aircraft is sent home"


def test_a_survey_aircraft_keeps_its_servos_to_itself(
    client, auth, armed_vehicle, monkeypatch
):
    """The valve command drives a servo or relay channel. On an aircraft
    carrying no sprayer, that channel is something else."""
    order = []
    armed_vehicle._mission_kind = "survey"
    monkeypatch.setattr(
        armed_vehicle, "send_command_long",
        lambda *a, **kw: order.append(kw.get("label", "command")) or {},
    )
    monkeypatch.setattr(
        armed_vehicle, "set_mode",
        lambda mode, **kw: order.append(f"mode:{mode}") or {},
    )

    client.post("/api/mavlink/command", json={"action": "rtl"}, headers=auth)
    assert order == ["mode:RTL"]


def test_force_arming_needs_the_server_to_allow_it(client, auth, monkeypatch):
    monkeypatch.delenv("MAVLINK_ALLOW_FORCE_ARM", raising=False)
    response = client.post(
        "/api/mavlink/command", json={"action": "arm", "force": True}, headers=auth
    )
    assert response.status_code == 403
    assert "MAVLINK_ALLOW_FORCE_ARM" in response.get_json()["message"]


def test_a_cloud_server_explains_that_it_cannot_reach_a_drone(
    client, auth, monkeypatch
):
    """A data centre has no telemetry radio and nothing on the field network
    can send to it. Without this the operator waits out the heartbeat timeout
    and reads "no heartbeat", which sounds like a problem with the aircraft."""
    monkeypatch.setenv("RAILWAY_ENVIRONMENT", "production")
    response = client.post(
        "/api/mavlink/connect", json={"url": "udpin:0.0.0.0:14550"}, headers=auth
    )
    assert response.status_code == 409
    assert "ground-station" in response.get_json()["message"]


# ── which device on the link is the aircraft ──────────────────────────────


class _Msg:
    """A stand-in MAVLink message: fields as attributes, ids off the wire."""

    def __init__(self, type_name, system=1, component=1, **fields):
        self._type = type_name
        self._system = system
        self._component = component
        self.__dict__.update(fields)

    def get_type(self):
        return self._type

    def get_srcSystem(self):
        return self._system

    def get_srcComponent(self):
        return self._component


def _heartbeat(system=1, component=1, vehicle_type=2, autopilot=3, base_mode=0,
               custom_mode=0):
    return _Msg(
        "HEARTBEAT", system, component, type=vehicle_type, autopilot=autopilot,
        base_mode=base_mode, custom_mode=custom_mode, system_status=4,
    )


def test_only_a_flight_controller_counts_as_the_vehicle():
    """A real link carries heartbeats from more than the autopilot: the
    aircraft's camera and gimbal, a companion computer, and the pilot's own
    ground station. Locking onto one of those addresses every command to a
    device that ignores it."""
    assert is_vehicle_heartbeat(_heartbeat())                       # the copter
    # a ground station, a camera, a gimbal, a companion computer
    assert not is_vehicle_heartbeat(_heartbeat(255, 190, 6, 8))
    assert not is_vehicle_heartbeat(_heartbeat(1, 100, 30, 8))
    assert not is_vehicle_heartbeat(_heartbeat(1, 154, 26, 8))
    assert not is_vehicle_heartbeat(_heartbeat(1, 191, 18, 8))


def test_connect_waits_for_the_autopilot_not_the_first_heartbeat(monkeypatch):
    """pymavlink hands over whichever heartbeat arrives first. Taking that one
    leaves the link addressing a camera — and, because the aircraft's own
    heartbeats are then ignored, showing "no signal" beside a healthy drone."""
    # link.py binds this very module object as `mavutil`, so patching the
    # factory here is what the connect below will call.
    mavutil = pytest.importorskip("pymavlink.mavutil")

    replies = [
        _heartbeat(255, 190, 6, 8),   # the pilot's ground station
        _heartbeat(7, 100, 30, 8),    # the aircraft's camera
        _heartbeat(7, 1),             # the flight controller
    ]
    master = MagicMock()
    master.recv_match.side_effect = lambda **kw: replies.pop(0) if replies else None
    monkeypatch.setattr(mavutil, "mavlink_connection", lambda *a, **kw: master)

    instance = MavlinkLink()
    try:
        snapshot = instance.connect(url="udpin:0.0.0.0:14550", timeout=5)
        assert (instance._target_system, instance._target_component) == (7, 1)
        assert snapshot["autopilot"] == "ardupilot"
        assert snapshot["alive"] is True
    finally:
        instance.disconnect()


def test_another_device_on_the_link_cannot_move_the_readings():
    """A companion computer heartbeats on the aircraft's own system id —
    disarmed, no flight mode. Folded into the snapshot it makes the drone
    flicker between armed and disarmed on the operator's screen."""
    pytest.importorskip("pymavlink")
    instance = MavlinkLink()
    instance._master = MagicMock()
    instance._master.mode_mapping.return_value = {"AUTO": 3, "GUIDED": 4}
    instance._target_system, instance._target_component = 1, 1

    instance._absorb(_heartbeat(1, 1, base_mode=128, custom_mode=3), "HEARTBEAT")
    assert instance._telemetry["armed"] is True
    assert instance._telemetry["mode"] == "AUTO"

    instance._absorb(_heartbeat(1, 191, 18, 8), "HEARTBEAT")
    assert instance._telemetry["armed"] is True

    instance._absorb(
        _Msg("GPS_RAW_INT", system=2, fix_type=3, satellites_visible=9),
        "GPS_RAW_INT",
    )
    assert instance._telemetry["gps_fix"] is None


# ── the mission upload handshake ──────────────────────────────────────────


def _mission_vehicle(instance, *, late_clear_ack=False, reject_with=None):
    """A fake vehicle that plays the mission protocol back at the link.

    Replies are dispatched from inside the send call, which is what a fast
    link does in practice: SITL answers in well under a millisecond.
    """
    master = MagicMock()
    state = {"count": 0}

    def ack(result=0):
        instance._dispatch(
            _Msg("MISSION_ACK", type=result, target_system=255), "MISSION_ACK"
        )

    def request(seq):
        instance._dispatch(
            _Msg("MISSION_REQUEST", seq=seq, target_system=255), "MISSION_REQUEST"
        )

    def clear_all(*_a, **_kw):
        if not late_clear_ack:
            ack()

    def count(_ts, _tc, count_value, *_a, **_kw):
        state["count"] = count_value
        if reject_with is not None:
            ack(reject_with)
            return
        if late_clear_ack:
            ack()  # the clear's answer, arriving after the transfer began
        request(0)

    def item(_ts, _tc, seq, *_a, **_kw):
        request(seq + 1) if seq + 1 < state["count"] else ack()

    master.mav.mission_clear_all_send.side_effect = clear_all
    master.mav.mission_count_send.side_effect = count
    master.mav.mission_item_int_send.side_effect = item

    instance._master = master
    instance._target_system, instance._target_component = 1, 1
    instance._source_system = 255
    instance._last_heartbeat = time.time()
    return master


def _block_items():
    return build_mission_items(normalise_waypoints(BLOCK, 30.0), altitude_m=30.0)


def test_upload_serves_every_request_and_ends_on_the_acknowledgement():
    instance = MavlinkLink()
    master = _mission_vehicle(instance)
    items = _block_items()

    result = instance.upload_items(items)

    assert result["uploaded"] == len(items)
    assert master.mav.mission_item_int_send.call_count == len(items)


def test_a_late_clear_acknowledgement_is_not_a_finished_upload():
    """The clear-all's answer can arrive after the new transfer has started on
    a slow radio. Read as this upload's ACK it ends the transfer with nothing
    sent, and the aircraft flies whatever plan it already had."""
    instance = MavlinkLink()
    master = _mission_vehicle(instance, late_clear_ack=True)
    items = _block_items()

    result = instance.upload_items(items)

    assert result["uploaded"] == len(items)
    assert master.mav.mission_item_int_send.call_count == len(items)


def test_a_rejected_mission_says_what_the_vehicle_reported():
    instance = MavlinkLink()
    _mission_vehicle(instance, reject_with=4)  # MAV_MISSION_NO_SPACE

    with pytest.raises(MavlinkError, match="room for"):
        instance.upload_items(_block_items())


def test_the_plan_is_not_replaced_under_a_flying_aircraft():
    """ArduPilot accepts a new mission in mid-air and carries on from the same
    item number in it — which is not where the operator thinks it is."""
    instance = MavlinkLink()
    _mission_vehicle(instance)
    instance._telemetry["armed"] = True

    with pytest.raises(MavlinkError, match="armed"):
        instance.upload_items(_block_items())


# ── refusing to launch ────────────────────────────────────────────────────


def test_a_launch_waits_for_a_3d_gps_fix():
    instance, _calls, patches = _recording_link(armed=False)
    instance._telemetry["gps_fix"] = 1

    for p in patches:
        p.start()
    try:
        with pytest.raises(MavlinkError, match="GPS"):
            instance.start_mission()
    finally:
        for p in patches:
            p.stop()


def test_a_launch_refuses_a_nearly_flat_battery():
    instance, _calls, patches = _recording_link(armed=False)
    instance._telemetry["battery_percent"] = 11

    for p in patches:
        p.start()
    try:
        with pytest.raises(MavlinkError, match="Battery"):
            instance.start_mission()
    finally:
        for p in patches:
            p.stop()


def test_a_return_home_during_the_launch_cancels_it():
    """RTL and MISSION_START race each other: the launch's last step would put
    the aircraft straight back into AUTO, a second after the operator asked it
    to come home."""
    instance, calls, patches = _recording_link(armed=True)
    patches[0] = patch.object(
        instance, "set_mode",
        side_effect=lambda mode, **kw: (
            calls.append(f"mode:{mode}"), instance.interrupt(), {}
        )[-1],
    )

    for p in patches:
        p.start()
    try:
        with pytest.raises(MavlinkError, match="cancelled"):
            instance.start_mission()
    finally:
        for p in patches:
            p.stop()

    assert "mission_start" not in calls


def test_hold_prefers_brake_to_loiter():
    """In Copter, LOITER climbs and sinks with the throttle stick — and during
    an autonomous flight that stick sits at the bottom, so "hold" would bring
    the aircraft down into the crop. BRAKE ignores the sticks."""
    instance, calls, patches = _recording_link(
        modes=("GUIDED", "AUTO", "LOITER", "BRAKE")
    )

    for p in patches:
        p.start()
    try:
        instance.hold()
    finally:
        for p in patches:
            p.stop()

    assert calls == ["mode:BRAKE"]


def test_force_arming_is_off_unless_the_server_allows_it(monkeypatch):
    monkeypatch.delenv("MAVLINK_ALLOW_FORCE_ARM", raising=False)
    instance = MavlinkLink()
    instance._master = MagicMock()

    with pytest.raises(MavlinkError, match="switched off"):
        instance.arm(force=True)


def test_a_px4_vehicle_is_told_plainly_that_it_will_not_be_flown():
    """The missions, the launch sequence and DO_SPRAYER are all ArduPilot's.
    Telemetry still works, which is worth saying rather than failing oddly."""
    instance = MavlinkLink()
    instance._master = MagicMock()
    instance._autopilot = 12  # MAV_AUTOPILOT_PX4

    with pytest.raises(MavlinkError, match="PX4"):
        instance.start_mission()
    with pytest.raises(MavlinkError, match="PX4"):
        instance.upload_items(_block_items())
