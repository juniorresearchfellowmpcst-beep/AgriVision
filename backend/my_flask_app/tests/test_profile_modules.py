"""Tests for the modules that back the Profile, Settings, Disease and Reports
screens: pilot credentials, user preferences, the sync summary, disease-scan
history and field-report export.

These are the features the app used to fake with hard-coded data, so the thing
worth guarding is that each endpoint returns *real* derived state — an expiry
badge computed from the stored date, sync counts computed from actual rows —
rather than a constant that happens to look plausible.
"""

import io
from datetime import date, timedelta

import cv2
import numpy as np
import pytest

from app import create_app
from app.core.database import db

BLOCK_WAYPOINTS = [{"lat": 23.1918, "lon": 77.4202}, {"lat": 23.1920, "lon": 77.4207}]


@pytest.fixture()
def client():
    app = create_app()
    app.config.update(
        TESTING=True,
        SQLALCHEMY_DATABASE_URI="sqlite:///:memory:",
        JWT_SECRET_KEY="test-secret",
    )

    with app.app_context():
        db.drop_all()
        db.create_all()

    with app.test_client() as client:
        client.application = app
        yield client

    with app.app_context():
        db.session.remove()
        db.drop_all()


@pytest.fixture()
def auth(client):
    """Signed-in headers for a fresh account."""
    creds = {"name": "Test Pilot", "email": "pilot@example.com", "password": "secret123"}
    client.post("/api/auth/signup", json=creds)
    response = client.post(
        "/api/auth/signin",
        json={"email": creds["email"], "password": creds["password"]},
    )
    token = response.get_json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _leaf_photo(spotted=True):
    """A green leaf on a plain background, optionally with brown lesions."""
    img = np.full((240, 240, 3), 245, np.uint8)
    cv2.ellipse(img, (120, 120), (85, 55), 0, 0, 360, (60, 150, 70), -1)
    if spotted:
        for centre in ((95, 105), (140, 130), (115, 145)):
            cv2.circle(img, centre, 11, (30, 70, 130), -1)
    return cv2.imencode(".jpg", img)[1].tobytes()


# ── Pilot credentials ─────────────────────────────────────────────────────


def test_new_account_is_seeded_with_blank_required_paperwork(client, auth):
    body = client.get("/api/credentials", headers=auth).get_json()

    labels = [c["label"] for c in body["credentials"]]
    assert "DRONE PILOT LICENCE" in labels
    assert "INSURANCE POLICY" in labels
    # Seeded rows are empty, not pre-filled with invented licence numbers.
    assert all(c["identifier"] is None for c in body["credentials"])
    assert all(c["value"] == "—" for c in body["credentials"])


def test_status_is_derived_from_the_expiry_date(client, auth):
    credential_id = client.get("/api/credentials", headers=auth).get_json()[
        "credentials"
    ][0]["id"]

    def set_expiry(days_from_today):
        response = client.put(
            f"/api/credentials/{credential_id}",
            headers=auth,
            json={
                "expires_on": (
                    date.today() + timedelta(days=days_from_today)
                ).isoformat()
            },
        )
        return response.get_json()["credential"]

    assert set_expiry(400)["status"] == "valid"
    assert set_expiry(30)["status"] == "expiring"   # inside the 90-day window
    assert set_expiry(-1)["status"] == "expired"


def test_credential_without_an_expiry_never_lapses(client, auth):
    response = client.post(
        "/api/credentials",
        headers=auth,
        json={"label": "PERMANENT RATING", "kind": "certification"},
    )
    credential = response.get_json()["credential"]
    assert credential["status"] == "valid"
    assert credential["days_until_expiry"] is None


def test_counts_let_the_app_badge_the_profile(client, auth):
    credentials = client.get("/api/credentials", headers=auth).get_json()["credentials"]
    client.put(
        f"/api/credentials/{credentials[0]['id']}",
        headers=auth,
        json={"expires_on": (date.today() - timedelta(days=5)).isoformat()},
    )
    client.put(
        f"/api/credentials/{credentials[1]['id']}",
        headers=auth,
        json={"expires_on": (date.today() + timedelta(days=10)).isoformat()},
    )

    body = client.get("/api/credentials", headers=auth).get_json()
    assert body["expired_count"] == 1
    assert body["expiring_count"] == 1


def test_expiry_before_issue_is_rejected(client, auth):
    credential_id = client.get("/api/credentials", headers=auth).get_json()[
        "credentials"
    ][0]["id"]
    response = client.put(
        f"/api/credentials/{credential_id}",
        headers=auth,
        json={"issued_on": "2026-01-01", "expires_on": "2025-01-01"},
    )
    assert response.status_code == 400


def test_credentials_require_a_login(client):
    assert client.get("/api/credentials").status_code == 401
    assert client.post("/api/credentials", json={"label": "X"}).status_code == 401


def test_cannot_touch_another_pilots_credential(client, auth):
    credential_id = client.get("/api/credentials", headers=auth).get_json()[
        "credentials"
    ][0]["id"]

    client.post(
        "/api/auth/signup",
        json={"name": "Other", "email": "other@example.com", "password": "secret123"},
    )
    other = client.post(
        "/api/auth/signin",
        json={"email": "other@example.com", "password": "secret123"},
    ).get_json()["access_token"]
    other_auth = {"Authorization": f"Bearer {other}"}

    response = client.put(
        f"/api/credentials/{credential_id}",
        headers=other_auth,
        json={"identifier": "stolen"},
    )
    assert response.status_code == 403


# ── Preferences ───────────────────────────────────────────────────────────


def test_preferences_default_to_on(client, auth):
    body = client.get("/api/users/me/preferences", headers=auth).get_json()
    assert body["preferences"] == {
        "mission_updates": True,
        "ai_alerts": True,
        "field_reports": True,
        "auto_sync": True,
        "push_notifications": True,
    }


def test_partial_update_leaves_other_toggles_alone(client, auth):
    body = client.put(
        "/api/users/me/preferences", headers=auth, json={"ai_alerts": False}
    ).get_json()

    assert body["preferences"]["ai_alerts"] is False
    assert body["preferences"]["mission_updates"] is True
    assert body["changed"] == ["ai_alerts"]


def test_preferences_persist_and_ride_along_on_the_profile(client, auth):
    client.put("/api/users/me/preferences", headers=auth, json={"auto_sync": False})

    assert (
        client.get("/api/users/me/preferences", headers=auth).get_json()[
            "preferences"
        ]["auto_sync"]
        is False
    )
    # The Profile screen gets them in the same payload as the rest of /me,
    # so its toggles render without a second request.
    assert (
        client.get("/api/users/me", headers=auth).get_json()["user"]["preferences"][
            "auto_sync"
        ]
        is False
    )


def test_no_op_update_is_reported_as_no_change(client, auth):
    body = client.put(
        "/api/users/me/preferences", headers=auth, json={"ai_alerts": True}
    ).get_json()
    assert body["changed"] == []


def test_unknown_preference_is_rejected_not_ignored(client, auth):
    response = client.put(
        "/api/users/me/preferences", headers=auth, json={"dark_mode": True}
    )
    assert response.status_code == 400
    assert "dark_mode" in response.get_json()["message"]


# ── Sync summary ──────────────────────────────────────────────────────────


def test_sync_summary_counts_real_records(client, auth):
    body = client.get("/api/users/me/sync-status", headers=auth).get_json()
    by_key = {item["key"]: item for item in body["items"]}
    assert set(by_key) == {"mission_logs", "detection_frames", "field_reports"}
    assert by_key["mission_logs"]["total"] == 0

    client.post(
        "/api/mission/missions",
        headers=auth,
        json={"name": "Block A", "waypoints": BLOCK_WAYPOINTS},
    )

    by_key = {
        item["key"]: item
        for item in client.get("/api/users/me/sync-status", headers=auth).get_json()[
            "items"
        ]
    }
    assert by_key["mission_logs"]["total"] == 1
    # A planned flight has not been closed out, so it is still open.
    assert by_key["mission_logs"]["pending"] == 1
    assert by_key["mission_logs"]["status"] == "pending"


def test_completed_mission_is_no_longer_pending(client, auth):
    mission_id = client.post(
        "/api/mission/missions",
        headers=auth,
        json={"name": "Block A", "waypoints": BLOCK_WAYPOINTS},
    ).get_json()["mission"]["id"]

    client.patch(
        f"/api/mission/missions/{mission_id}/status",
        headers=auth,
        json={"status": "done"},
    )

    by_key = {
        item["key"]: item
        for item in client.get("/api/users/me/sync-status", headers=auth).get_json()[
            "items"
        ]
    }
    assert by_key["mission_logs"]["pending"] == 0
    assert by_key["mission_logs"]["status"] == "synced"


# ── Disease scan history ──────────────────────────────────────────────────


def test_identify_records_the_scan(client, auth):
    response = client.post(
        "/api/disease/identify",
        headers=auth,
        content_type="multipart/form-data",
        data={
            "image": (io.BytesIO(_leaf_photo()), "leaf.jpg"),
            "field_name": "Block A",
        },
    )
    body = response.get_json()
    assert response.status_code == 200
    assert isinstance(body["scan_id"], int)

    scans = client.get("/api/disease/scans", headers=auth).get_json()["scans"]
    assert len(scans) == 1
    assert scans[0]["field_name"] == "Block A"
    assert scans[0]["filename"] == "leaf.jpg"
    # Which engine answered matters — a heuristic and a trained model are not
    # equally trustworthy, and history should say which one this was.
    assert scans[0]["engine"] in ("model", "heuristic")


def test_history_is_newest_first(client, auth):
    for name in ("first.jpg", "second.jpg"):
        client.post(
            "/api/disease/identify",
            headers=auth,
            content_type="multipart/form-data",
            data={"image": (io.BytesIO(_leaf_photo()), name)},
        )

    scans = client.get("/api/disease/scans", headers=auth).get_json()["scans"]
    assert [s["filename"] for s in scans] == ["second.jpg", "first.jpg"]


def test_a_scan_can_be_reopened_with_its_full_diagnosis(client, auth):
    scan_id = client.post(
        "/api/disease/identify",
        headers=auth,
        content_type="multipart/form-data",
        data={"image": (io.BytesIO(_leaf_photo()), "leaf.jpg")},
    ).get_json()["scan_id"]

    scan = client.get(f"/api/disease/scans/{scan_id}", headers=auth).get_json()["scan"]
    assert scan["detail"]["disease"]["name"]
    assert "solutions" in scan["detail"]


def test_missing_scan_returns_404(client, auth):
    assert client.get("/api/disease/scans/999999", headers=auth).status_code == 404


# ── Report export ─────────────────────────────────────────────────────────


@pytest.fixture()
def analysis_record(client):
    """A stored analysis run to export."""
    from app.services.analysis_service import AnalysisService

    with client.application.app_context():
        record = AnalysisService.record_analysis(
            {
                "job_id": "job-1",
                "primary_index": "NDVI",
                "calibrated": True,
                "report": {
                    "health_score": 72.4,
                    "health_label": "Moderate stress",
                    "flags": [
                        {
                            "issue": "Low vigour in the north strip",
                            "severity": "high",
                            "index": "ndvi",
                        }
                    ],
                },
                "risk": {"distribution": {"high": 0.21, "medium": 0.34, "low": 0.45}},
            },
            user_id=None,
            field_name="Block A North",
        )
        return record.id


def test_csv_export_carries_the_numbers_and_the_detections(client, analysis_record):
    response = client.get(f"/api/analysis/reports/{analysis_record}/export?format=csv")
    assert response.status_code == 200
    assert "text/csv" in response.headers["Content-Type"]

    text = response.data.decode("utf-8-sig")
    assert "72 / 100" in text
    assert "Moderate stress" in text
    assert "21%" in text  # high-risk area
    assert "Low vigour in the north strip" in text


def test_export_filename_identifies_the_field_and_date(client, analysis_record):
    response = client.get(f"/api/analysis/reports/{analysis_record}/export?format=csv")
    assert "agrivision-block-a-north" in response.headers["Content-Disposition"]
    assert response.headers["Content-Disposition"].endswith('.csv"')


def test_pdf_export_is_a_real_pdf(client, analysis_record):
    pytest.importorskip("matplotlib", reason="PDF export needs matplotlib")

    response = client.get(f"/api/analysis/reports/{analysis_record}/export?format=pdf")
    assert response.status_code == 200
    assert response.headers["Content-Type"].startswith("application/pdf")
    assert response.data[:5] == b"%PDF-"


def test_export_defaults_to_csv(client, analysis_record):
    response = client.get(f"/api/analysis/reports/{analysis_record}/export")
    assert response.status_code == 200
    assert "text/csv" in response.headers["Content-Type"]


def test_unknown_export_format_is_rejected(client, analysis_record):
    response = client.get(
        f"/api/analysis/reports/{analysis_record}/export?format=docx"
    )
    assert response.status_code == 400
    assert "docx" in response.get_json()["message"]


def test_exporting_a_missing_report_returns_404(client):
    assert client.get("/api/analysis/reports/999999/export").status_code == 404
