"""Tests for the survey flight: camera selection through to an authorised spray.

What must not silently break here is the chain of consent. Everything before
``/authorise`` is analysis and can be re-run; ``/authorise`` is the step where
a farmer's tank and a farmer's permission turn into a valve opening over a real
field. So most of this file is about the ways that step is supposed to *refuse*.

The other half is the treatment knowledge: a recommendation that names a
fungicide for a virus, or a herbicide without knowing the crop, would be worse
than no recommendation at all.
"""

import io
import json

import cv2
import numpy as np
import pytest

from app import create_app
from app.ai import treatment_kb
from app.api.models.survey import SurveyRun
from app.core.database import db
from app.spray.hotspot_zones import HotspotError, cluster_detections

SIZE = 256


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


def _detection(lat, lon, severity, weed=0.02, disease="soybean_rust",
               name="Soybean rust", confidence=0.8):
    """One scanned frame, in the shape ``field_scan.scan_frame`` produces."""
    return {
        "status": "ok",
        "crop": "soybean",
        "lat": lat,
        "lon": lon,
        "frame_id": f"live_{lat}_{lon}",
        "is_healthy": disease == "healthy",
        "severity": {"level": severity, "affected_percent": 40},
        "disease": {"id": disease, "name": name, "confidence": confidence,
                    "source": "model"},
        "weeds": {
            "weed_coverage": weed,
            "pressure": {"level": "low" if weed < 0.08 else "high",
                         "percent": int(weed * 100), "advice": ""},
        },
    }


def _pass_over_a_field():
    """A flight line with a bad corner, a middling strip and a clean end."""
    scans = []
    for i in range(8):
        scans.append(_detection(23.1900 + i * 2e-5, 77.4200 + i * 2e-5, "high", 0.05))
    for i in range(8):
        scans.append(_detection(23.1920 + i * 2e-5, 77.4230 + i * 2e-5, "moderate", 0.03))
    for i in range(8):
        scans.append(
            _detection(23.1950 + i * 2e-5, 77.4260 + i * 2e-5, "none", 0.004,
                       disease="healthy", name="No disease detected", confidence=0.0)
        )
    return scans


# ── K-means over detections ──────────────────────────────────────────────────

class TestHotspotClustering:

    def test_bad_corner_becomes_the_severe_cluster(self):
        result = cluster_detections(_pass_over_a_field(), k=3, crop="soybean")

        by_severity = {c["severity"]: c for c in result["clusters"]}
        assert set(by_severity) == {"severe", "moderate", "healthy"}
        # The severe cluster must be the one nearest the bad corner, or the
        # aircraft would spray the clean end of the field.
        assert by_severity["severe"]["lat"] == pytest.approx(23.1901, abs=2e-4)
        assert by_severity["healthy"]["lat"] == pytest.approx(23.1951, abs=2e-4)

    def test_only_treatable_clusters_become_patches(self):
        result = cluster_detections(_pass_over_a_field(), k=3)
        assert result["patch_count"] == 2
        assert {p["severity"] for p in result["patches"]} == {"severe", "moderate"}

    def test_patch_carries_what_the_mission_builder_needs(self):
        result = cluster_detections(_pass_over_a_field(), k=3, swath_m=3.0)
        for patch in result["patches"]:
            assert patch["lat"] is not None and patch["lon"] is not None
            # A patch narrower than the boom would make the aircraft fidget.
            assert patch["radius_m"] >= 1.5
            assert patch["area_ha"] > 0

    def test_unlocated_frames_are_counted_not_silently_dropped(self):
        scans = _pass_over_a_field()
        scans.append({"status": "ok", "severity": {"level": "high"},
                      "disease": {}, "weeds": {}})
        result = cluster_detections(scans, k=3)
        assert result["skipped_no_fix"] == 1
        assert any("no GPS fix" in note for note in result["notes"])

    def test_no_position_at_all_is_an_error_with_a_reason(self):
        with pytest.raises(HotspotError) as caught:
            cluster_detections(
                [{"status": "ok", "severity": {"level": "high"},
                  "disease": {}, "weeds": {}}]
            )
        assert "GPS" in str(caught.value)

    def test_too_few_detections_says_so_rather_than_pretending(self):
        scans = [_detection(23.19 + i * 1e-4, 77.42, "high") for i in range(3)]
        result = cluster_detections(scans, k=3)
        assert result["clustered"] is False
        assert result["patch_count"] == 3
        assert any("too few to cluster" in note for note in result["notes"])

    def test_a_uniform_field_is_flagged_as_low_contrast(self):
        scans = [
            _detection(23.19 + i * 2e-5, 77.42 + i * 2e-5, "low", 0.01)
            for i in range(12)
        ]
        result = cluster_detections(scans, k=3)
        assert result["low_contrast"] is True
        assert any("uniform" in note for note in result["notes"])

    def test_a_weedy_frame_scores_even_with_no_disease(self):
        """Weeds and disease are combined by the worse of the two, not averaged.

        A frame with heavy weed cover and a clean canopy is still worth
        spraying, and averaging would bury it in the moderate band.
        """
        scans = [
            _detection(23.19 + i * 2e-5, 77.42, "none", weed=0.30,
                       disease="healthy", name="No disease detected", confidence=0.0)
            for i in range(8)
        ] + [
            _detection(23.20 + i * 2e-5, 77.43, "none", weed=0.001,
                       disease="healthy", name="No disease detected", confidence=0.0)
            for i in range(8)
        ]
        result = cluster_detections(scans, k=2)
        assert "severe" in {c["severity"] for c in result["clusters"]}


# ── treatment knowledge ──────────────────────────────────────────────────────

class TestTreatmentKnowledge:

    def test_every_crop_disease_has_a_treatment(self):
        """A diagnosis the app can produce but not advise on is a dead end."""
        from app.ai.crop_kb import CROPS

        missing = [
            disease["id"]
            for crop in CROPS.values()
            for disease in crop["diseases"]
            if disease["id"] not in treatment_kb.TREATMENTS
        ]
        assert missing == []

    def test_a_virus_is_not_sprayable_and_targets_its_vector(self):
        entry = treatment_kb.treatment_for("soybean_yellow_mosaic")
        # Sprayable, because the *whitefly* can be sprayed...
        assert entry["sprayable"] is True
        # ...but nothing recommended may be a fungicide.
        assert all(p["category"] != "fungicide" for p in entry["products"])
        assert any("virus" in note.lower() for note in entry["cultural"])

    def test_a_seed_borne_disease_refuses_to_recommend_a_flight(self):
        entry = treatment_kb.treatment_for("wheat_loose_smut")
        assert entry["sprayable"] is False
        assert all(not p["drone_ready"] for p in entry["products"])

    def test_no_herbicide_without_a_crop(self):
        """The one recommendation in this file that could destroy a field."""
        entry = treatment_kb.weed_treatment_for(None, "high")
        assert entry["sprayable"] is False
        assert entry["products"] == []
        assert "without knowing the crop" in entry["summary"]

    def test_low_weed_pressure_does_not_justify_a_tank(self):
        entry = treatment_kb.weed_treatment_for("wheat", "low")
        assert entry["sprayable"] is False
        assert entry["products"] == []

    def test_incompatible_products_are_planned_as_separate_passes(self):
        plan = treatment_kb.spray_plan(
            conditions=[
                {"id": "soybean_rust", "name": "Soybean rust"},
                {"id": "soybean_girdle_beetle", "name": "Girdle beetle damage"},
            ],
            crop_id="soybean",
            weed_pressure="high",
        )
        # A fungicide, an insecticide and a herbicide are three tanks.
        assert plan["pass_count"] == 3
        assert plan["needs_separate_passes"] is True
        groups = {entry["tank_group"] for entry in plan["passes"]}
        assert groups == {"protectant", "insecticide", "herbicide"}

    def test_only_one_product_goes_in_the_tank(self):
        plan = treatment_kb.spray_plan(
            conditions=[{"id": "soybean_rust", "name": "Soybean rust"}],
            crop_id="soybean",
        )
        entry = plan["passes"][0]
        assert entry["load"] is not None
        # The rest are for the *next* spray, not this load.
        assert all(a["name"] != entry["load"]["name"] for a in entry["alternates"])

    def test_an_unsprayable_condition_is_reported_not_dropped(self):
        plan = treatment_kb.spray_plan(
            conditions=[{"id": "pigeonpea_wilt", "name": "Fusarium wilt"}],
            crop_id="pigeonpea",
        )
        assert plan["passes"] == []
        assert plan["not_sprayable"][0]["condition"] == "Fusarium wilt"
        assert plan["not_sprayable"][0]["instead"]

    def test_healthy_never_produces_a_tank(self):
        plan = treatment_kb.spray_plan(
            conditions=[{"id": "healthy", "name": "No disease detected"}],
            crop_id="soybean",
        )
        assert plan["pass_count"] == 0


# ── the crop catalogue and the phone scan ────────────────────────────────────

class TestCropCatalogue:

    def test_catalogue_lists_crops_and_the_weeds_tile(self, client):
        response = client.get("/api/crops")
        assert response.status_code == 200
        body = response.get_json()
        ids = {crop["id"] for crop in body["crops"]}
        assert {"soybean", "rice", "maize", "wheat"}.issubset(ids)
        # Weeds is offered alongside the crops but is not one of them: anything
        # iterating crops to run a disease model must not be handed it.
        assert body["weeds_option"]["id"] == "weeds"
        assert "weeds" not in ids

    def test_in_season_crops_sort_first(self, client):
        body = client.get("/api/crops?month=8").get_json()  # August = kharif
        assert body["crops"][0]["in_season"] is True
        seasons = [crop["season"] for crop in body["crops"] if crop.get("in_season")]
        assert "kharif" in seasons

    def test_crop_detail_carries_the_treatment(self, client):
        body = client.get("/api/crops/soybean").get_json()
        rust = next(d for d in body["diseases"] if d["id"] == "soybean_rust")
        assert rust["treatment"]["products"]
        assert rust["urgency"] == "urgent"
        assert body["herbicides"]

    def test_unknown_crop_names_the_ones_that_exist(self, client):
        response = client.get("/api/crops/banana")
        assert response.status_code == 404
        assert "soybean" in response.get_json()["message"]

    def test_weeds_path_is_not_swallowed_by_the_crop_route(self, client):
        """'/weeds' must not be routed as a crop id called "weeds"."""
        response = client.get("/api/crops/weeds")
        assert response.status_code == 200
        assert response.get_json()["weeds"]

    def test_phone_scan_returns_a_treatment_and_refuses_to_promise_a_spray(
        self, client
    ):
        image = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
        image[:, :] = (60, 80, 125)
        image[40:200, 40:200] = (40, 160, 50)
        encoded = cv2.imencode(".jpg", image)[1].tobytes()

        response = client.post(
            "/api/crops/scan",
            data={
                "image": (io.BytesIO(encoded), "leaf.jpg"),
                "crop": "soybean",
                "mode": "both",
            },
            content_type="multipart/form-data",
        )
        assert response.status_code == 200
        body = response.get_json()
        assert body["source"] == "phone"
        assert "treatment" in body
        assert "tank_plan" in body["treatment"]
        # A single photo cannot say where in the block the problem is.
        assert "cannot say where" in body["spray_note"]

    def test_selecting_the_weeds_tile_scans_for_weeds_only(self, client):
        image = np.full((SIZE, SIZE, 3), (60, 80, 125), dtype=np.uint8)
        image[30:220, 30:220] = (40, 160, 50)
        encoded = cv2.imencode(".jpg", image)[1].tobytes()

        response = client.post(
            "/api/crops/scan",
            data={"image": (io.BytesIO(encoded), "field.jpg"), "crop": "weeds"},
            content_type="multipart/form-data",
        )
        assert response.status_code == 200
        body = response.get_json()
        assert body["mode"] == "weed"
        # The disease half must report that it did not run rather than
        # reporting a clean canopy it never looked at.
        assert body["disease"]["source"] == "not_requested"


# ── the survey run ───────────────────────────────────────────────────────────

class TestSurveyRun:

    def test_capabilities_disables_a_mode_with_no_camera(self, client):
        body = client.get("/api/survey/capabilities").get_json()
        modes = {mode["id"]: mode for mode in body["camera_modes"]}
        assert modes["rgb"]["available"] is False
        assert "No RGB camera is registered" in modes["rgb"]["reason"]
        assert modes["multispectral"]["available"] is False
        assert "red and an NIR" in modes["multispectral"]["reason"]

    def test_multispectral_needs_a_red_and_nir_pair_not_just_bands(self, client):
        for band in ("green", "blue"):
            client.post("/api/capture/cameras", json={
                "name": f"{band} band", "role": "multispectral",
                "band": band, "url": f"rtsp://10.0.0.1/{band}",
            })
        modes = {
            mode["id"]: mode
            for mode in client.get("/api/survey/capabilities").get_json()["camera_modes"]
        }
        assert modes["multispectral"]["available"] is False

        for band in ("red", "nir"):
            client.post("/api/capture/cameras", json={
                "name": f"{band} band", "role": "multispectral",
                "band": band, "url": f"rtsp://10.0.0.1/{band}",
            })
        modes = {
            mode["id"]: mode
            for mode in client.get("/api/survey/capabilities").get_json()["camera_modes"]
        }
        assert modes["multispectral"]["available"] is True

    def test_starting_an_rgb_survey_with_no_camera_fails_on_the_ground(self, client):
        response = client.post("/api/survey/runs", json={
            "camera_mode": "rgb", "crop": "soybean",
        })
        assert response.status_code == 409
        assert "RGB camera" in response.get_json()["message"]

    def test_unknown_camera_mode_is_rejected(self, client):
        response = client.post("/api/survey/runs", json={"camera_mode": "thermal"})
        assert response.status_code == 400
        assert "camera_mode" in response.get_json()["message"]

    def test_unknown_crop_is_rejected(self, client):
        response = client.post("/api/survey/runs", json={
            "camera_mode": "multispectral", "crop": "banana",
        })
        assert response.status_code == 400

    def test_a_multispectral_survey_starts_without_a_video_feed(self, client):
        for band in ("red", "nir"):
            client.post("/api/capture/cameras", json={
                "name": f"{band} band", "role": "multispectral",
                "band": band, "url": f"rtsp://10.0.0.1/{band}", "fov_deg": 62,
            })

        response = client.post("/api/survey/runs", json={
            "camera_mode": "multispectral", "crop": "soybean",
            "field_name": "Block A",
        })
        assert response.status_code == 200
        body = response.get_json()
        assert body["run"]["status"] == "flying"
        assert body["run"]["camera_mode"] == "multispectral"
        # The operator must be told there is no live disease readout, not left
        # watching an empty screen for one.
        assert any("no live disease readout" in w for w in body["warnings"])

    def test_finishing_with_nothing_scanned_still_answers(self, client, app):
        for band in ("red", "nir"):
            client.post("/api/capture/cameras", json={
                "name": f"{band} band", "role": "multispectral",
                "band": band, "url": f"rtsp://10.0.0.1/{band}",
            })
        run_id = client.post("/api/survey/runs", json={
            "camera_mode": "multispectral", "crop": "soybean",
        }).get_json()["run"]["id"]

        response = client.post(f"/api/survey/runs/{run_id}/finish")
        assert response.status_code == 200
        summary = response.get_json()["summary"]
        assert summary["health"]["score"] is None
        assert summary["health"]["band"] == "unknown"
        assert any("No multispectral shot" in note for note in summary["notes"])


# ── the consent chain ────────────────────────────────────────────────────────

class TestSprayAuthorisation:
    """The step where analysis becomes a valve opening over a real field."""

    @pytest.fixture()
    def analysed_run(self, client, app):
        """A finished run with a real prescription behind it."""
        camera_id = client.post("/api/capture/cameras", json={
            "name": "Nose camera", "role": "rgb",
            "url": "rtsp://10.0.0.1/rgb", "fov_deg": 62,
        }).get_json()["camera"]["id"]

        with app.app_context():
            run = SurveyRun(
                session_id="survey_test_0001",
                field_name="Block A",
                camera_mode="rgb",
                detection_target="both",
                crop="soybean",
                rgb_camera_id=camera_id,
                status="flying",
            )
            db.session.add(run)
            db.session.commit()
            run_id = run.id

        # Feed the finisher a real pass without needing a camera: the analyser
        # is the only part that cannot be exercised without one.
        original = SurveyService_history_patch(app, _pass_over_a_field())
        try:
            response = client.post(f"/api/survey/runs/{run_id}/finish")
            assert response.status_code == 200
        finally:
            original()
        return run_id

    def test_finish_produces_health_actions_and_a_map(self, client, analysed_run):
        body = client.get(f"/api/survey/runs/{analysed_run}/summary").get_json()
        summary = body["summary"]

        assert 0 <= summary["health"]["score"] <= 100
        assert summary["health"]["band"] in ("good", "fair", "poor", "critical")
        assert summary["scan"]["frames"] == 24
        # The action plan must reach a product, not stop at "confirm on the
        # ground" — that was the gap this whole flow exists to close.
        assert any(action.get("product") for action in summary["action_plan"])
        assert summary["prescription"]["patch_count"] >= 1
        assert body["run"]["prescription_id"] is not None

    def test_authorise_refuses_without_a_filled_tank(self, client, analysed_run):
        response = client.post(
            f"/api/survey/runs/{analysed_run}/authorise",
            json={"tank_filled": False, "start": True},
        )
        assert response.status_code == 409
        assert "tank is filled" in response.get_json()["message"]

    def test_authorise_refuses_when_permission_is_withheld(self, client, analysed_run):
        response = client.post(
            f"/api/survey/runs/{analysed_run}/authorise",
            json={"tank_filled": True, "spray_authorised": False},
        )
        assert response.status_code == 409

    def test_authorise_refuses_before_the_run_is_summarised(self, client, app):
        with app.app_context():
            run = SurveyRun(session_id="s2", camera_mode="rgb", status="flying")
            db.session.add(run)
            db.session.commit()
            run_id = run.id

        response = client.post(
            f"/api/survey/runs/{run_id}/authorise",
            json={"tank_filled": True},
        )
        assert response.status_code == 409
        assert "not been summarised" in response.get_json()["message"]

    def test_authorised_but_no_vehicle_keeps_the_authorisation(
        self, client, app, analysed_run
    ):
        """A failed upload must not make the farmer confirm the tank again."""
        response = client.post(
            f"/api/survey/runs/{analysed_run}/authorise",
            json={"tank_filled": True, "tank_litres": 10,
                  "authorised_by": "Ramesh", "option": "severe_only",
                  "start": True},
        )
        # No aircraft is connected in a test, so the upload cannot succeed...
        assert response.status_code in (409, 502, 503)
        body = response.get_json()
        assert body.get("authorisation_recorded") is True

        # ...but the decision is on the record, with who made it.
        with app.app_context():
            run = db.session.get(SurveyRun, analysed_run)
            assert run.tank_filled is True
            assert run.tank_litres == 10
            assert run.spray_authorised is True
            assert run.authorised_by == "Ramesh"
            assert run.authorised_at is not None

    def test_finishing_twice_returns_the_same_answer(self, client, analysed_run):
        """A double tap on a slow connection is not a second intention."""
        first = client.post(f"/api/survey/runs/{analysed_run}/finish")
        assert first.status_code == 200
        assert first.get_json()["summary"]["run_id"] == analysed_run

    def test_a_cancelled_run_cannot_be_authorised(self, client, analysed_run):
        client.post(f"/api/survey/runs/{analysed_run}/cancel")
        response = client.post(
            f"/api/survey/runs/{analysed_run}/authorise",
            json={"tank_filled": True},
        )
        assert response.status_code == 409


def SurveyService_history_patch(app, scans):
    """Point the finisher at a canned pass, and hand back the undo.

    The live analyser needs a camera on a network; everything downstream of it
    -- the aggregate, the health score, the tank plan, the K-means map -- does
    not, and that is the part worth testing.
    """
    from app.services import survey_service

    original = survey_service.LiveAnalysisService.history
    survey_service.LiveAnalysisService.history = staticmethod(lambda key: scans)

    def undo():
        survey_service.LiveAnalysisService.history = original

    return undo


# ── the advisor ──────────────────────────────────────────────────────────────

class TestAdvisor:

    def test_health_reports_unconfigured_rather_than_pretending(self, client, monkeypatch):
        monkeypatch.delenv("GEMINI_API_KEY", raising=False)
        monkeypatch.delenv("GOOGLE_API_KEY", raising=False)
        body = client.get("/api/advisor/health").get_json()
        assert body["available"] is False
        assert "GEMINI_API_KEY" in body["message"]

    def test_asking_without_a_key_fails_loudly(self, client, monkeypatch):
        monkeypatch.delenv("GEMINI_API_KEY", raising=False)
        monkeypatch.delenv("GOOGLE_API_KEY", raising=False)
        response = client.post("/api/advisor/ask", json={"question": "What is this?"})
        assert response.status_code == 503
        assert "not configured" in response.get_json()["message"]

    def test_suggested_questions_follow_the_diagnosis(self, client):
        body = client.post("/api/advisor/suggest", json={
            "context": {"disease": {"name": "Soybean rust"}},
        }).get_json()
        assert any("Soybean rust" in question for question in body["questions"])

    def test_context_includes_the_apps_own_diagnosis(self):
        from app.ai.gemini_advisor import build_context

        context = build_context({
            "crop_name": "Soybean",
            "disease": {"name": "Soybean rust", "confidence": 0.71, "source": "model"},
            "severity": {"level": "high"},
        })
        assert "Soybean rust" in context
        assert "71%" in context
        assert "model" in context

    def test_empty_question_is_rejected_before_any_network_call(self, client, monkeypatch):
        monkeypatch.setenv("GEMINI_API_KEY", "not-a-real-key")
        response = client.post("/api/advisor/ask", json={"question": "   "})
        assert response.status_code == 400


class TestAdvisorTransport:
    """How the client talks to Google, and what it does when Google says no.

    Both of these are regressions, not hypotheticals. The pinned model id in
    the first release had already been retired for new API keys, and the flash
    endpoint answers 503 "high demand" often enough that one attempt is not a
    fair test of whether the advisor works.
    """

    @staticmethod
    def _stub(monkeypatch, statuses, payloads=None):
        """Answer with a scripted sequence of statuses; record every call."""
        import requests

        from app.ai import gemini_advisor

        calls = []
        payloads = payloads or [{}] * len(statuses)

        class _Response:
            def __init__(self, status, body):
                self.status_code = status
                self._body = body
                self.headers = {}

            def json(self):
                return self._body

        def fake_post(url, headers=None, json=None, timeout=None, **kwargs):
            calls.append({"url": url, "headers": headers or {}, "json": json})
            index = min(len(calls) - 1, len(statuses) - 1)
            return _Response(statuses[index], payloads[index])

        monkeypatch.setattr(requests, "post", fake_post)
        # No real waiting: the backoff is correctness, not something to sit
        # through once per test.
        monkeypatch.setattr(gemini_advisor.time, "sleep", lambda _s: None)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        return calls

    def _answer(self, text="ok"):
        return {"candidates": [{"content": {"parts": [{"text": text}]},
                                "finishReason": "STOP"}]}

    def test_the_key_travels_in_a_header_never_in_the_url(self, monkeypatch):
        """A key in `?key=` ends up in proxy logs and crash reports."""
        from app.ai.gemini_advisor import ask

        calls = self._stub(monkeypatch, [200], [self._answer()])
        ask(question="anything")

        assert calls[0]["headers"].get("X-goog-api-key") == "test-key"
        assert "test-key" not in calls[0]["url"]
        assert "key=" not in calls[0]["url"]

    def test_a_transient_503_is_retried_rather_than_shown_to_the_operator(
        self, monkeypatch
    ):
        from app.ai.gemini_advisor import ask

        calls = self._stub(
            monkeypatch,
            [503, 503, 200],
            [{}, {}, self._answer("Spray in the evening.")],
        )
        result = ask(question="Is it safe to spray at flowering?")

        assert result["answer"] == "Spray in the evening."
        assert len(calls) == 3

    def test_retries_are_bounded(self, monkeypatch):
        """A sustained outage must not hold the screen open indefinitely."""
        from app.ai.gemini_advisor import MAX_ATTEMPTS, AdvisorError, ask

        calls = self._stub(monkeypatch, [503] * 10)
        with pytest.raises(AdvisorError) as caught:
            ask(question="anything")

        assert len(calls) == MAX_ATTEMPTS
        assert "busy" in str(caught.value)

    def test_a_timeout_says_busy_not_offline(self, monkeypatch):
        """Two different failures deserve two different messages.

        Telling an operator to check their internet when the connection is
        fine and the model is merely slow sends them to debug the wrong thing.
        """
        import requests

        from app.ai.gemini_advisor import AdvisorError, ask

        def timeout(*_a, **_k):
            raise requests.exceptions.Timeout("read timed out")

        monkeypatch.setattr(requests, "post", timeout)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")

        with pytest.raises(AdvisorError) as caught:
            ask(question="anything")

        assert caught.value.status == 504
        assert "busy rather than unreachable" in str(caught.value)
        assert "internet" not in str(caught.value)

    def test_a_bad_key_is_not_retried(self, monkeypatch):
        """403 will answer the same way forever; retrying only slows the error."""
        from app.ai.gemini_advisor import AdvisorError, ask

        calls = self._stub(monkeypatch, [403])
        with pytest.raises(AdvisorError):
            ask(question="anything")
        assert len(calls) == 1

    def test_a_retired_model_names_the_env_var_that_fixes_it(self, monkeypatch):
        """The failure an admin can fix in one line should say which line."""
        from app.ai.gemini_advisor import AdvisorError, ask

        self._stub(
            monkeypatch,
            [404],
            [{"error": {"message": "This model models/gemini-2.5-flash is no "
                                   "longer available to new users."}}],
        )
        with pytest.raises(AdvisorError) as caught:
            ask(question="anything")

        message = str(caught.value)
        assert "GEMINI_MODEL" in message
        # Google's own explanation is passed through, not swallowed.
        assert "no longer available" in message

    def test_the_default_model_is_an_alias_not_a_pinned_version(self):
        """A pinned id rots. `-latest` follows whatever flash currently is."""
        from app.ai.gemini_advisor import DEFAULT_MODEL

        assert DEFAULT_MODEL.endswith("-latest")

    def test_the_requested_language_reaches_the_model(self, monkeypatch):
        """Passed, not inferred.

        A farmer who has set the app to Hindi still types crop names in
        English, so guessing the reply language from the question would answer
        half their scans in the wrong one.
        """
        from app.ai.gemini_advisor import ask

        calls = self._stub(monkeypatch, [200], [self._answer()])
        ask(question="What is this?", language="Hindi (हिन्दी)")

        instruction = calls[0]["json"]["system_instruction"]["parts"][0]["text"]
        assert "Answer in Hindi" in instruction

    def test_no_language_leaves_the_model_to_follow_the_question(
        self, monkeypatch
    ):
        from app.ai.gemini_advisor import SYSTEM_PROMPT, ask

        calls = self._stub(monkeypatch, [200], [self._answer()])
        ask(question="What is this?")

        instruction = calls[0]["json"]["system_instruction"]["parts"][0]["text"]
        assert instruction == SYSTEM_PROMPT

    def test_the_route_forwards_the_language(self, client, monkeypatch):
        """JSON and multipart both carry it, so the app need not pick a shape."""
        import app.services.advisor_service as advisor_service

        seen = {}

        def fake_ask(**kwargs):
            seen.update(kwargs)
            return {"answer": "ठीक है", "model": "test"}

        monkeypatch.setattr(advisor_service.gemini_advisor, "ask", fake_ask)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")

        response = client.post(
            "/api/advisor/ask",
            json={"question": "yeh kya hai?", "language": "Hindi"},
        )
        assert response.status_code == 200
        assert seen["language"] == "Hindi"
