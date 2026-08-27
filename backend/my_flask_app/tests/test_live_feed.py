"""Watching and analysing the drone's feed while it is flying.

The still-frame path is covered in ``test_capture_routes.py``. What is checked
here is the live path: that a camera is opened once no matter how many things
are watching it, that a feed which drops is reported as reconnecting rather
than silently replaying its last frame, that the relay speaks MJPEG a plain
HTTP client can read, and that the rolling analysis describes the frames it
actually scanned.

Cameras are simulated with local image files, which
:class:`~app.capture.live.LiveStream` polls exactly as it polls a snapshot
endpoint — same code path, no network.
"""

import time

import cv2
import numpy as np
import pytest

from app import create_app
from app.capture.live import (
    MJPEG_BOUNDARY,
    STATE_LIVE,
    STATE_RECONNECTING,
    LiveStream,
    StreamHub,
    encode_jpeg,
    mjpeg_stream,
)
from app.core.database import db

SIZE = 192


def _canopy_frame(green: int = 150) -> np.ndarray:
    """A frame that looks enough like a crop canopy for the detectors."""
    frame = np.full((SIZE, SIZE, 3), (60, 80, 125), dtype=np.uint8)
    frame[40:160, 40:160] = (40, green, 50)
    return frame


@pytest.fixture(scope="module")
def app(tmp_path_factory):
    application = create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret",
    })
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


@pytest.fixture()
def camera_file(tmp_path):
    """A file standing in for a snapshot camera, rewritable mid-test."""
    path = tmp_path / "feed.png"
    cv2.imwrite(str(path), _canopy_frame())
    return path


def _wait_for(predicate, timeout=8.0, interval=0.05):
    """Poll until true — reader threads are asynchronous by design."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


# ── the stream itself ────────────────────────────────────────────────────

def test_a_stream_publishes_frames_from_its_camera(camera_file):
    stream = LiveStream("cam", str(camera_file))
    stream.subscribe()
    stream.start()
    try:
        got = stream.latest(timeout=8.0)
        assert got is not None, "the reader never published a frame"
        frame, seq, _stamp = got
        assert frame.shape[:2] == (SIZE, SIZE)
        assert seq >= 1

        status = stream.status()
        assert status["state"] == STATE_LIVE
        assert status["live"] is True
        assert status["width"] == SIZE
    finally:
        stream.unsubscribe()
        stream.stop(wait=True)


def test_latest_waits_for_a_frame_newer_than_the_one_already_seen(camera_file):
    """A relay must not re-send the frame it just sent."""
    stream = LiveStream("cam", str(camera_file))
    stream.subscribe()
    stream.start()
    try:
        first = stream.latest(timeout=8.0)
        assert first is not None
        second = stream.latest(after_seq=first[1], timeout=8.0)
        assert second is not None
        assert second[1] > first[1]
    finally:
        stream.unsubscribe()
        stream.stop(wait=True)


def test_a_dead_camera_is_reported_as_reconnecting_not_as_live(tmp_path):
    """The honest answer to "no picture" is "reconnecting", not a stale frame."""
    stream = LiveStream("cam", str(tmp_path / "never-existed.png"))
    stream.subscribe()
    stream.start()
    try:
        assert _wait_for(lambda: stream.status()["state"] == STATE_RECONNECTING)
        status = stream.status()
        assert status["live"] is False
        assert status["last_error"]
        # No frame was ever produced, so a viewer gets nothing rather than
        # something misleading.
        assert stream.latest(timeout=0.5) is None
    finally:
        stream.unsubscribe()
        stream.stop(wait=True)


def test_a_camera_that_comes_back_starts_publishing_again(tmp_path):
    path = tmp_path / "late.png"
    stream = LiveStream("cam", str(path))
    stream.subscribe()
    stream.start()
    try:
        assert _wait_for(lambda: stream.status()["state"] == STATE_RECONNECTING)
        cv2.imwrite(str(path), _canopy_frame())
        assert _wait_for(lambda: stream.status()["state"] == STATE_LIVE, timeout=15.0)
        assert stream.latest(timeout=5.0) is not None
    finally:
        stream.unsubscribe()
        stream.stop(wait=True)


def test_the_hub_gives_two_viewers_one_camera_session(camera_file):
    """The whole point of the relay: one connection to the camera."""
    hub = StreamHub()
    try:
        first = hub.open("cam", str(camera_file))
        second = hub.open("cam", str(camera_file))
        assert first is second
        assert first.status()["viewers"] == 2

        hub.release(second)
        assert first.status()["viewers"] == 1
    finally:
        hub.shutdown()


def test_joining_a_stream_that_is_shutting_down_gets_a_fresh_one(camera_file):
    """The narrow race that would otherwise leave a viewer on a dead feed.

    A stream can stop between being found alive and being joined. Attaching to
    it would give the operator a black rectangle that never recovers, so the
    hub must notice the refusal and build a new session instead.
    """
    hub = StreamHub()
    try:
        first = hub.open("cam", str(camera_file))
        hub.release(first)
        # Simulate losing the race: the stream is stopping, but is still in
        # the hub and its thread has not finished unwinding.
        first.stop()
        assert first.subscribe() is False, "a stopping stream accepted a viewer"

        second = hub.open("cam", str(camera_file))
        assert second is not first
        assert second.latest(timeout=8.0) is not None
    finally:
        hub.shutdown()


def test_repointing_a_camera_replaces_its_session(camera_file, tmp_path):
    other = tmp_path / "other.png"
    cv2.imwrite(str(other), _canopy_frame(green=90))

    hub = StreamHub()
    try:
        first = hub.open("cam", str(camera_file))
        hub.release(first)
        second = hub.open("cam", str(other))
        assert second is not first
        assert second.url == str(other)
    finally:
        hub.shutdown()


def test_a_stream_releases_its_camera_once_nobody_is_watching(camera_file, monkeypatch):
    import app.capture.live as live

    # The real idle timeout is 20s; nobody should wait that long in a test.
    monkeypatch.setattr(live, "IDLE_SHUTDOWN_S", 0.2)

    hub = StreamHub()
    try:
        stream = hub.open("cam", str(camera_file))
        assert stream.latest(timeout=8.0) is not None
        hub.release(stream)
        assert _wait_for(lambda: not stream.alive), "the camera was never released"
    finally:
        hub.shutdown()


# ── the relay ────────────────────────────────────────────────────────────

def test_encode_jpeg_rescues_a_16_bit_band():
    """A multispectral band must not relay as a black rectangle."""
    band = (np.arange(SIZE * SIZE, dtype=np.uint16).reshape(SIZE, SIZE) % 4096) * 16
    jpeg = encode_jpeg(band, max_width=128)
    assert jpeg is not None
    decoded = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
    assert decoded.shape[1] == 128
    assert decoded.max() > 40, "the band was crushed to black"


def test_mjpeg_stream_yields_readable_jpeg_parts(camera_file):
    stream = LiveStream("cam", str(camera_file))
    stream.subscribe()
    stream.start()
    try:
        assert stream.latest(timeout=8.0) is not None

        parts = []
        for chunk in mjpeg_stream(stream, fps=30, quality=60, max_width=128):
            parts.append(chunk)
            if len(parts) >= 2:
                break

        for part in parts:
            assert part.startswith(b"--" + MJPEG_BOUNDARY.encode())
            assert b"Content-Type: image/jpeg" in part
            body = part.split(b"\r\n\r\n", 1)[1].rstrip(b"\r\n")
            decoded = cv2.imdecode(np.frombuffer(body, np.uint8), cv2.IMREAD_COLOR)
            assert decoded is not None
            assert decoded.shape[1] == 128
    finally:
        stream.unsubscribe()
        stream.stop(wait=True)


def test_the_relay_keeps_the_connection_alive_while_a_feed_is_down(tmp_path, monkeypatch):
    """A silent socket is indistinguishable from a hung server."""
    import app.capture.live as live

    monkeypatch.setattr(live, "_KEEPALIVE_EVERY_S", 0.2)

    stream = LiveStream("cam", str(tmp_path / "absent.png"))
    stream.subscribe()
    stream.start()
    try:
        assert _wait_for(lambda: stream.status()["state"] == STATE_RECONNECTING)
        chunk = next(iter(mjpeg_stream(stream, fps=5)))
        assert b"X-AgriVision-Status: waiting" in chunk
        assert b"image/jpeg" not in chunk
    finally:
        stream.unsubscribe()
        stream.stop(wait=True)


# ── over HTTP ────────────────────────────────────────────────────────────

def _register(client, camera_file, role="rgb", band=None):
    payload = {"name": "Nose camera", "role": role, "url": str(camera_file)}
    if band:
        payload["band"] = band
    response = client.post("/api/capture/cameras", json=payload)
    assert response.status_code == 201, response.get_json()
    return response.get_json()["camera"]["id"]


def test_health_advertises_the_live_relay(client):
    live = client.get("/api/capture/health").get_json()["live"]
    assert live["supported"] is True
    assert live["relay"] == "mjpeg"


def test_a_single_live_frame_comes_back_as_a_jpeg(client, camera_file):
    camera_id = _register(client, camera_file)
    response = client.get(f"/api/capture/cameras/{camera_id}/frame?width=160")
    assert response.status_code == 200, response.get_data()[:400]
    assert response.mimetype == "image/jpeg"

    decoded = cv2.imdecode(np.frombuffer(response.data, np.uint8), cv2.IMREAD_COLOR)
    assert decoded is not None
    assert decoded.shape[1] == 160


def test_an_absurd_width_is_clamped_rather_than_honoured(client, camera_file):
    """A 1-pixel preview is a request worth refusing quietly."""
    camera_id = _register(client, camera_file)
    response = client.get(f"/api/capture/cameras/{camera_id}/frame?width=2")
    assert response.status_code == 200
    decoded = cv2.imdecode(np.frombuffer(response.data, np.uint8), cv2.IMREAD_COLOR)
    assert decoded.shape[1] == 160


def test_an_unreachable_camera_answers_with_the_reason(client, tmp_path):
    camera_id = _register(client, tmp_path / "nothing-here.png")
    response = client.get(f"/api/capture/cameras/{camera_id}/frame?wait=1")
    assert response.status_code == 504
    body = response.get_json()
    assert body["status"] == "error"
    # The operator has to be told what to check, not just that it failed.
    assert body["message"]
    assert body["stream"]["state"] in (STATE_RECONNECTING, "starting")


def test_a_disabled_camera_will_not_stream(client, camera_file):
    camera_id = _register(client, camera_file)
    client.patch(f"/api/capture/cameras/{camera_id}", json={"enabled": False})
    response = client.get(f"/api/capture/cameras/{camera_id}/stream")
    assert response.status_code == 409
    assert "switched off" in response.get_json()["message"]


def test_streaming_a_camera_that_does_not_exist_is_a_404(client):
    assert client.get("/api/capture/cameras/9999/stream").status_code == 404


def test_the_stream_endpoint_is_multipart_mjpeg(client, camera_file):
    camera_id = _register(client, camera_file)
    response = client.get(
        f"/api/capture/cameras/{camera_id}/stream?fps=30&width=128",
        buffered=False,
    )
    try:
        assert response.status_code == 200
        assert "multipart/x-mixed-replace" in response.headers["Content-Type"]
        assert MJPEG_BOUNDARY in response.headers["Content-Type"]
        # nginx would otherwise buffer the relay into uselessness.
        assert response.headers["X-Accel-Buffering"] == "no"

        chunk = next(response.response)
        assert chunk.startswith(b"--" + MJPEG_BOUNDARY.encode())
    finally:
        response.close()


def test_live_status_lists_the_open_feeds(client, camera_file):
    camera_id = _register(client, camera_file)
    client.get(f"/api/capture/cameras/{camera_id}/frame?wait=8")

    streams = client.get("/api/capture/live").get_json()["streams"]
    assert any(s["key"] == str(camera_id) for s in streams)

    closed = client.delete(f"/api/capture/cameras/{camera_id}/stream").get_json()
    assert closed["status"] == "ok"


# ── analysing the live feed ──────────────────────────────────────────────

def test_live_analysis_reports_what_it_scanned(client, camera_file):
    camera_id = _register(client, camera_file)
    started = client.post(
        f"/api/capture/cameras/{camera_id}/analyze",
        json={"crop": "soybean", "interval_s": 1, "window": 5},
    )
    assert started.status_code == 200, started.get_json()

    try:
        def scanned_something():
            body = client.get(
                f"/api/capture/cameras/{camera_id}/analyze"
            ).get_json()
            return bool(body.get("analysis", {}).get("scanned"))

        assert _wait_for(scanned_something, timeout=30.0, interval=0.5), (
            "the analyser never scanned a frame"
        )

        analysis = client.get(
            f"/api/capture/cameras/{camera_id}/analyze"
        ).get_json()["analysis"]

        assert analysis["running"] is True
        assert analysis["crop"] == "soybean"
        assert analysis["latest"]["disease"]["name"]
        assert analysis["latest"]["weeds"]["weed_coverage"] is not None
        # The rolling answer must describe the frames actually scanned.
        assert analysis["rolling"]["frames"] == analysis["window"]
        assert analysis["stream"]["state"] == STATE_LIVE

        frames = client.get(
            f"/api/capture/cameras/{camera_id}/analyze/frames"
        ).get_json()["frames"]
        assert len(frames) == analysis["window"]
    finally:
        client.delete(f"/api/capture/cameras/{camera_id}/analyze")


def test_live_analysis_refuses_a_multispectral_band(client, camera_file):
    """A single band is not what the weed/disease detectors read."""
    camera_id = _register(client, camera_file, role="multispectral", band="nir")
    response = client.post(f"/api/capture/cameras/{camera_id}/analyze", json={})
    assert response.status_code == 400
    assert "spray prescription" in response.get_json()["message"]


def test_live_analysis_rejects_an_absurd_interval(client, camera_file):
    camera_id = _register(client, camera_file)
    response = client.post(
        f"/api/capture/cameras/{camera_id}/analyze", json={"interval_s": 0.01}
    )
    assert response.status_code == 400
    assert "interval_s" in response.get_json()["message"]


def test_asking_about_an_unwatched_camera_is_not_an_error(client, camera_file):
    camera_id = _register(client, camera_file)
    body = client.get(f"/api/capture/cameras/{camera_id}/analyze").get_json()
    assert body["running"] is False
    assert body["analysis"] is None


def test_stopping_an_analysis_that_is_not_running_is_a_404(client, camera_file):
    camera_id = _register(client, camera_file)
    assert client.delete(
        f"/api/capture/cameras/{camera_id}/analyze"
    ).status_code == 404


def test_deleting_a_camera_stops_its_live_work(client, camera_file):
    """A removed camera must not leave a reader thread on the old URL."""
    from app.capture.live import hub

    camera_id = _register(client, camera_file)
    client.post(
        f"/api/capture/cameras/{camera_id}/analyze", json={"interval_s": 1}
    )
    assert _wait_for(lambda: hub.get(str(camera_id)) is not None)

    assert client.delete(f"/api/capture/cameras/{camera_id}").status_code == 200
    assert _wait_for(
        lambda: hub.get(str(camera_id)) is None
        or not hub.get(str(camera_id)).alive
    )
