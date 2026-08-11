"""End-to-end HTTP tests for capture → spray prescription → field scan.

This is the chain the feature actually is: frames come off the drone's
cameras, the multispectral ones become a K-means prescription the operator
chooses from, and the RGB ones become a weed/disease scan. Each unit is tested
elsewhere; what is checked here is that they hand off to each other over HTTP,
and that the steps which command hardware refuse to act without a vehicle.
"""

import io

import cv2
import numpy as np
import pytest

from app import create_app
from app.core.database import db

SIZE = 256
SOIL = (60, 80, 125)
CROP_GREEN = (40, 160, 50)


@pytest.fixture(scope="module")
def app(tmp_path_factory):
    """One app for the module — building it costs seconds, and every test in
    here wants the same one. Isolation comes from the per-test table reset
    below, not from a fresh Flask instance."""
    application = create_app({
        "TESTING": True,
        # Isolated from the developer's real database. This MUST go through
        # create_app: overriding the config afterwards leaves the engine bound
        # to the dev database, and drop_all() then deletes real data.
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret",
    })
    # Keep captured frames and rendered maps out of the real instance folder.
    application.instance_path = str(tmp_path_factory.mktemp("instance"))
    return application


@pytest.fixture()
def client(app):
    with app.app_context():
        db.drop_all()
        db.create_all()

    with app.test_client() as test_client:
        yield test_client

    with app.app_context():
        db.session.remove()
        db.drop_all()


def _png(array) -> bytes:
    ok, buffer = cv2.imencode(".png", array)
    assert ok
    return buffer.tobytes()


def _band_pair():
    """A field with a stressed block in one corner, as red + NIR bands."""
    red = np.full((SIZE, SIZE), 30, dtype=np.uint8)
    nir = np.full((SIZE, SIZE), 200, dtype=np.uint8)
    red[20:90, 20:90] = 55
    nir[20:90, 20:90] = 62
    red[170:230, 170:230] = 60
    nir[170:230, 170:230] = 120
    return _png(red), _png(nir)


def _canopy_frame():
    image = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    image[:, :] = SOIL
    for x in range(10, SIZE, 40):
        image[:, x:x + 16] = CROP_GREEN
    ok, buffer = cv2.imencode(".jpg", image)
    assert ok
    return buffer.tobytes()


def _upload_bands(client, session_id="sess_test"):
    red, nir = _band_pair()
    response = client.post(
        "/api/capture/upload",
        data={
            "red": (io.BytesIO(red), "red.png"),
            "nir": (io.BytesIO(nir), "nir.png"),
            "session_id": session_id,
            "field_name": "Block A",
            "lat": "23.2599",
            "lon": "77.4126",
            "alt_m": "30",
            "heading_deg": "0",
        },
        content_type="multipart/form-data",
    )
    assert response.status_code == 200, response.get_json()
    return response.get_json()


# ── camera registry ──────────────────────────────────────────────────────

def test_no_cameras_until_the_operator_adds_them(client):
    """Nothing is seeded: a camera that does not exist cannot take a picture,
    and a fake one in the list is worse than an empty list."""
    body = client.get("/api/capture/cameras").get_json()
    assert body["cameras"] == []
    assert body["ready_for_multispectral"] is False
    assert body["has_rgb"] is False


def test_multispectral_camera_must_declare_its_band(client):
    response = client.post(
        "/api/capture/cameras",
        json={"name": "MS cam", "role": "multispectral", "url": "rtsp://10.0.0.5/1"},
    )
    assert response.status_code == 400
    assert "band" in response.get_json()["message"]


def test_registering_the_rig_makes_it_ready(client):
    for band in ("red", "nir"):
        response = client.post(
            "/api/capture/cameras",
            json={
                "name": f"{band} band",
                "role": "multispectral",
                "band": band,
                "url": f"rtsp://10.0.0.5/{band}",
                "fov_deg": 62,
            },
        )
        assert response.status_code == 201, response.get_json()

    client.post(
        "/api/capture/cameras",
        json={"name": "IP camera", "role": "rgb", "url": "rtsp://10.0.0.6/live"},
    )

    body = client.get("/api/capture/cameras").get_json()
    assert body["ready_for_multispectral"] is True
    assert body["has_rgb"] is True
    assert sorted(body["multispectral_bands"]) == ["nir", "red"]


def test_unknown_band_is_rejected(client):
    response = client.post(
        "/api/capture/cameras",
        json={"role": "multispectral", "band": "ultraviolet", "url": "rtsp://x/1"},
    )
    assert response.status_code == 400


def test_testing_an_unreachable_feed_answers_200_with_the_reason(client):
    """'The camera is unreachable' is information the settings screen needs to
    show, not a server error."""
    response = client.post(
        "/api/capture/cameras/test", json={"url": "rtsp://192.0.2.1/nope"}
    )
    assert response.status_code == 200
    assert response.get_json()["reachable"] is False


# ── capture ──────────────────────────────────────────────────────────────

def test_uploaded_bands_become_an_analysable_shot(client):
    body = _upload_bands(client)
    assert body["analysable"] is True
    assert sorted(body["bands"]) == ["nir", "red"]
    assert body["shot_id"]
    assert all(frame["lat"] == pytest.approx(23.2599) for frame in body["frames"])


def test_captured_frames_are_grouped_into_shots(client):
    shot = _upload_bands(client)
    body = client.get(f"/api/capture/frames?session_id={shot['session_id']}").get_json()
    assert len(body["shots"]) == 1
    assert body["shots"][0]["analysable"] is True
    assert len(body["frames"]) == 2


def test_capture_shoot_without_cameras_explains_itself(client):
    response = client.post("/api/capture/shoot", json={})
    assert response.status_code == 409
    assert "No cameras" in response.get_json()["message"]


def test_stored_frames_are_servable(client):
    body = _upload_bands(client)
    preview = next(f["preview_url"] for f in body["frames"] if f.get("preview_url"))
    path = preview.split("/api/capture/file/")[1]
    assert client.get(f"/api/capture/file/{path}").status_code == 200


# ── prescription ─────────────────────────────────────────────────────────

def test_prescribe_from_a_captured_shot(client):
    shot = _upload_bands(client)
    response = client.post(
        "/api/spray/prescribe", json={"shot_id": shot["shot_id"], "fov_deg": 62}
    )
    assert response.status_code == 200, response.get_json()

    body = response.get_json()
    assert body["index"] == "ndvi"
    assert body["prescription_id"]
    assert body["coverage"]["georeferenced"] is True
    assert body["patches"], "the stressed block should become a sprayable patch"

    options = {option["id"]: option for option in body["options"]}
    assert options["severe_only"]["saving_percent"] > 0
    assert options["blanket"]["saving_percent"] == 0

    # The rendered map must be fetchable by the app.
    map_url = body["outputs"]["prescription_map"]
    assert client.get("/api/spray/output/" + map_url.split("/api/spray/output/")[1]).status_code == 200


def test_prescribe_needs_a_red_nir_pair(client):
    green = np.full((SIZE, SIZE), 120, dtype=np.uint8)
    upload = client.post(
        "/api/capture/upload",
        data={"green": (io.BytesIO(_png(green)), "green.png")},
        content_type="multipart/form-data",
    ).get_json()

    response = client.post("/api/spray/prescribe", json={"shot_id": upload["shot_id"]})
    assert response.status_code == 409
    assert "red + NIR" in response.get_json()["message"]


def test_prescribe_without_a_shot_id_says_so(client):
    assert client.post("/api/spray/prescribe", json={}).status_code == 400


# ── plan / execute ───────────────────────────────────────────────────────

def _prescription_id(client):
    shot = _upload_bands(client)
    return client.post(
        "/api/spray/prescribe", json={"shot_id": shot["shot_id"], "fov_deg": 62}
    ).get_json()["prescription_id"]


def test_plan_returns_a_flyable_mission_without_touching_the_vehicle(client):
    prescription_id = _prescription_id(client)
    response = client.post(
        f"/api/spray/prescriptions/{prescription_id}/plan",
        json={"option": "severe_only"},
    )
    assert response.status_code == 200, response.get_json()

    body = response.get_json()
    assert body["items"], "a plan is a mission item list"
    assert body["summary"]["patches"] >= 1
    assert body["summary"]["has_rtl"] is True
    assert body["economics"]["saving_percent"] > 0
    # Nothing has been sent anywhere yet.
    assert body["status"] == "ok"


def test_plan_requires_an_explicit_choice(client):
    prescription_id = _prescription_id(client)
    response = client.post(f"/api/spray/prescriptions/{prescription_id}/plan", json={})
    assert response.status_code == 400
    assert "severe_only" in response.get_json()["message"]


def test_blanket_is_not_a_targeted_prescription(client):
    prescription_id = _prescription_id(client)
    response = client.post(
        f"/api/spray/prescriptions/{prescription_id}/plan", json={"option": "blanket"}
    )
    assert response.status_code == 400
    assert "blanket" in response.get_json()["message"].lower()


def test_execute_refuses_without_a_connected_vehicle(client):
    """The one call that opens a valve must fail loudly, not silently do
    nothing, when there is no aircraft on the wire."""
    prescription_id = _prescription_id(client)
    response = client.post(
        f"/api/spray/prescriptions/{prescription_id}/execute",
        json={"option": "severe_only", "start": True},
    )
    assert response.status_code in (409, 503)
    assert response.get_json()["status"] == "error"


def test_prescription_history_is_recorded(client):
    _prescription_id(client)
    body = client.get("/api/spray/prescriptions").get_json()
    assert len(body["prescriptions"]) == 1
    assert body["prescriptions"][0]["status"] == "proposed"


# ── field scan ───────────────────────────────────────────────────────────

def test_analyze_one_canopy_frame(client):
    response = client.post(
        "/api/fieldscan/analyze",
        data={
            "image": (io.BytesIO(_canopy_frame()), "frame.jpg"),
            "crop": "soybean",
            "field_name": "Block A",
        },
        content_type="multipart/form-data",
    )
    assert response.status_code == 200, response.get_json()

    body = response.get_json()
    assert body["crop"] == "soybean"
    assert body["weeds"]["method"] in ("inter-row", "appearance", "inconclusive", "none")
    assert body["disease"]["id"]
    assert body["scan_id"]
    assert body["actions"]


def test_analyze_without_an_image_says_so(client):
    response = client.post("/api/fieldscan/analyze", data={}, content_type="multipart/form-data")
    assert response.status_code == 400


def test_scan_a_whole_low_pace_pass(client):
    session_id = "sess_lowpass"
    for _ in range(3):
        response = client.post(
            "/api/capture/upload",
            data={
                "rgb": (io.BytesIO(_canopy_frame()), "frame.jpg"),
                "session_id": session_id,
                "lat": "23.26",
                "lon": "77.41",
            },
            content_type="multipart/form-data",
        )
        assert response.status_code == 200

    response = client.post(
        "/api/fieldscan/session", json={"session_id": session_id, "crop": "wheat"}
    )
    assert response.status_code == 200, response.get_json()

    body = response.get_json()
    assert body["summary"]["frames"] == 3
    assert body["summary"]["actions"]
    assert len(body["frames"]) == 3

    # The summary must be re-derivable from what was stored, without re-running
    # the scan over the whole pass.
    summary = client.get(f"/api/fieldscan/summary?session_id={session_id}").get_json()
    assert summary["summary"]["frames"] == 3


def test_scan_session_needs_rgb_frames(client):
    shot = _upload_bands(client, session_id="sess_bands_only")
    response = client.post(
        "/api/fieldscan/session", json={"session_id": shot["session_id"]}
    )
    assert response.status_code == 409
    assert "RGB" in response.get_json()["message"]


def test_catalog_lists_mp_crops_and_their_weeds(client):
    body = client.get("/api/fieldscan/catalog").get_json()
    ids = {crop["id"] for crop in body["crops"]}
    assert {"soybean", "rice", "wheat", "gram"}.issubset(ids)

    wheat = client.get("/api/fieldscan/catalog?crop=wheat").get_json()
    assert any(d["id"] == "wheat_yellow_rust" for d in wheat["diseases"])
    assert any(w["id"] == "phalaris_minor" for w in wheat["weeds"])


def test_health_reports_which_engine_answers(client):
    body = client.get("/api/fieldscan/health").get_json()
    # No model files configured in a test run.
    assert body["engines"] == {"disease": "heuristic", "weed": "heuristic"}
