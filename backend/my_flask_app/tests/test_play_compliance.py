"""Google Play requirements the backend carries.

* **Account deletion** (User Data policy): an app with sign-up must let people
  delete the account *and its data*, from the app and from the web.
* **Public legal pages**: the privacy policy URL on the store listing, and the
  web deletion page.
* **Reporting AI output** (AI-generated content policy): answers from the crop
  advisor can be reported from inside the app.

SQLite's foreign-key enforcement is switched on here, so a deletion that
removes a parent before its children fails in these tests the way it would on
PostgreSQL in production, instead of passing silently.
"""

import os
from datetime import date, datetime

import pytest
import sqlalchemy as sa

from app import create_app
from app.api.models.advisor_report import AdvisorReport
from app.api.models.analysis import AlertRecord, AnalysisRecord
from app.api.models.capture import CameraFeed, CaptureFrame
from app.api.models.credential import PilotCredential
from app.api.models.disease_scan import DiseaseScan
from app.api.models.drone import Drone
from app.api.models.field_scan import FieldScanRecord
from app.api.models.mission import Mission
from app.api.models.password_reset import PasswordResetOtp
from app.api.models.preference import UserPreference
from app.api.models.spray import SprayPrescription
from app.api.models.survey import SurveyRun
from app.api.models.user import User, UserProfile
from app.core.database import db
from app.core.security import hash_password

PASSWORD = "secret123"

# Every table an account owns, with the column that says so.
OWNED = [
    (AnalysisRecord, "user_id"),
    (SurveyRun, "user_id"),
    (FieldScanRecord, "user_id"),
    (SprayPrescription, "user_id"),
    (CaptureFrame, "user_id"),
    (CameraFeed, "user_id"),
    (DiseaseScan, "user_id"),
    (Mission, "user_id"),
    (Drone, "owner_id"),
    (PilotCredential, "user_id"),
    (UserPreference, "user_id"),
    (UserProfile, "user_id"),
    (AdvisorReport, "user_id"),
]


@pytest.fixture()
def app(tmp_path):
    application = create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret",
        "RATELIMIT_ENABLED": False,
    })
    application.instance_path = str(tmp_path / "instance")
    os.makedirs(application.instance_path, exist_ok=True)
    with application.app_context():
        db.session.execute(sa.text("PRAGMA foreign_keys=ON"))
        db.drop_all()
        db.create_all()
    yield application
    with application.app_context():
        db.session.remove()
        db.drop_all()


@pytest.fixture()
def client(app):
    with app.test_client() as test_client:
        yield test_client


_counter = [0]


def _make(model, **fields):
    """A row with every required column filled, whatever the model is.

    Reads the table's own column definitions, so this does not have to be
    updated each time a model gains a required field.
    """
    row = model()
    for column in model.__table__.columns:
        if column.primary_key or column.name in fields:
            continue
        if (column.nullable or column.default is not None
                or column.server_default is not None):
            continue
        _counter[0] += 1
        n = _counter[0]
        if isinstance(column.type, sa.Enum):
            value = column.type.enums[0]
        else:
            try:
                kind = column.type.python_type
            except NotImplementedError:
                kind = str
            if kind is bool:
                value = False
            elif kind is int:
                value = n
            elif kind is float:
                value = 1.0
            elif kind is datetime:
                value = datetime(2026, 1, 1)
            elif kind is date:
                value = date(2026, 1, 1)
            elif kind in (dict, list):
                value = kind()
            else:
                value = f"x{n}"
        setattr(row, column.name, value)
    for name, value in fields.items():
        setattr(row, name, value)
    db.session.add(row)
    db.session.flush()
    return row


def _user(email):
    user = User(username=email.split("@")[0], email=email,
                password=hash_password(PASSWORD))
    db.session.add(user)
    db.session.commit()
    return user.id


def _seed(uid, email, *, frame_path=None, preview_path=None, map_path=None,
          session_id=None):
    """One of everything an account can own, wired the way the app wires it."""
    camera = _make(CameraFeed, user_id=uid)
    frame = _make(CaptureFrame, user_id=uid, camera_id=camera.id,
                  **({"path": frame_path} if frame_path else {}),
                  **({"preview_path": preview_path} if preview_path else {}))
    _make(FieldScanRecord, user_id=uid, frame_id=frame.id)
    prescription = _make(SprayPrescription, user_id=uid,
                         **({"map_path": map_path} if map_path else {}))
    _make(SurveyRun, user_id=uid, rgb_camera_id=camera.id,
          prescription_id=prescription.id,
          session_id=session_id or f"sess-{uid}")
    analysis = _make(AnalysisRecord, user_id=uid)
    _make(AlertRecord, analysis_id=analysis.id)
    _make(DiseaseScan, user_id=uid)
    _make(Mission, user_id=uid)
    _make(Drone, owner_id=uid)
    _make(PilotCredential, user_id=uid)
    _make(UserPreference, user_id=uid)
    _make(UserProfile, user_id=uid)
    _make(AdvisorReport, user_id=uid, reason="wrong", answer="spray 5 L")
    _make(PasswordResetOtp, email=email)
    db.session.commit()
    return {"frame": frame.id, "camera": camera.id,
            "prescription": prescription.id}


def _token(client, email):
    response = client.post("/api/auth/signin",
                           json={"email": email, "password": PASSWORD})
    assert response.status_code == 200, response.get_json()
    return response.get_json()["access_token"]


def _delete(client, email, confirm=None):
    return client.delete(
        "/api/users/me",
        json={"confirm_email": email if confirm is None else confirm},
        headers={"Authorization": f"Bearer {_token(client, email)}"},
    )


def _owned_counts(uid):
    return {m.__tablename__: m.query.filter(getattr(m, c) == uid).count()
            for m, c in OWNED}


# ── deletion from the app ────────────────────────────────────────────────────

def test_deleting_an_account_removes_everything_it_owns(app, client):
    with app.app_context():
        alice = _user("alice@example.com")
        bob = _user("bob@example.com")
        _seed(alice, "alice@example.com")
        _seed(bob, "bob@example.com")

    response = _delete(client, "alice@example.com")
    assert response.status_code == 200, response.get_json()

    with app.app_context():
        assert db.session.get(User, alice) is None
        leftovers = {k: v for k, v in _owned_counts(alice).items() if v}
        assert leftovers == {}, f"rows survived the deletion: {leftovers}"
        assert PasswordResetOtp.query.filter_by(
            email="alice@example.com").count() == 0
        # Somebody else's data is none of this deletion's business.
        assert all(_owned_counts(bob).values()), _owned_counts(bob)
        assert db.session.get(User, bob) is not None


def test_another_users_rows_are_detached_not_deleted(app, client):
    """Bob's scan of Alice's frame keeps Bob's scan, minus the pointer."""
    with app.app_context():
        alice = _user("alice@example.com")
        bob = _user("bob@example.com")
        alice_ids = _seed(alice, "alice@example.com")
        bobs_scan = _make(FieldScanRecord, user_id=bob,
                          frame_id=alice_ids["frame"])
        bobs_run = _make(SurveyRun, user_id=bob, session_id="bob-run",
                         rgb_camera_id=alice_ids["camera"],
                         prescription_id=alice_ids["prescription"])
        db.session.commit()
        scan_id, run_id = bobs_scan.id, bobs_run.id

    assert _delete(client, "alice@example.com").status_code == 200

    with app.app_context():
        scan = db.session.get(FieldScanRecord, scan_id)
        run = db.session.get(SurveyRun, run_id)
        assert scan is not None and scan.frame_id is None
        assert run is not None
        assert run.rgb_camera_id is None and run.prescription_id is None


def test_a_wrong_confirmation_deletes_nothing(app, client):
    with app.app_context():
        alice = _user("alice@example.com")
        _seed(alice, "alice@example.com")

    response = _delete(client, "alice@example.com", confirm="bob@example.com")
    assert response.status_code == 400

    with app.app_context():
        assert db.session.get(User, alice) is not None
        assert all(_owned_counts(alice).values())


def test_the_confirmation_ignores_case_and_spaces(app, client):
    with app.app_context():
        _user("alice@example.com")
    response = _delete(client, "alice@example.com",
                       confirm="  Alice@Example.COM ")
    assert response.status_code == 200


def test_deletion_needs_a_signed_in_user(client):
    response = client.delete("/api/users/me",
                             json={"confirm_email": "alice@example.com"})
    assert response.status_code in (401, 422)


def test_files_are_removed_but_nothing_outside_storage(app, client, tmp_path):
    instance = app.instance_path
    frame_file = os.path.join(instance, "captures", "sess-a", "frame.jpg")
    preview_file = os.path.join(instance, "captures", "sess-a", "preview.jpg")
    session_file = os.path.join(instance, "spray_outputs", "sess-a", "map.png")
    outside = tmp_path / "not-ours.jpg"
    for path in (frame_file, preview_file, session_file):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "wb").write(b"jpg")
    outside.write_bytes(b"keep me")

    with app.app_context():
        alice = _user("alice@example.com")
        _seed(alice, "alice@example.com",
              frame_path=frame_file,              # absolute, inside storage
              preview_path="sess-a/preview.jpg",  # relative to captures/
              map_path=str(outside),              # absolute, OUTSIDE storage
              session_id="sess-a")

    assert _delete(client, "alice@example.com").status_code == 200

    assert not os.path.exists(frame_file)
    assert not os.path.exists(preview_file)
    assert not os.path.exists(os.path.dirname(session_file))
    # A row pointing outside the instance folder must never become a way to
    # delete a file the app does not own.
    assert outside.exists()


# ── the public pages ─────────────────────────────────────────────────────────

@pytest.mark.parametrize("url, heading", [
    ("/privacy", "AgriVision Privacy Policy"),
    ("/terms", "AgriVision Terms of Use"),
])
def test_the_legal_pages_are_public_html(client, url, heading):
    response = client.get(url)
    assert response.status_code == 200
    assert response.mimetype == "text/html"
    body = response.get_data(as_text=True)
    assert f"<h1>{heading}</h1>" in body
    assert "**" not in body, "markdown was printed, not rendered"


def test_the_privacy_policy_says_how_to_delete_an_account(client):
    body = client.get("/privacy").get_data(as_text=True)
    assert "/account/delete" in body
    assert "Delete account" in body


def test_the_renderer_never_turns_text_into_markup():
    from app.api.routes.legal_routes import _render
    rendered = _render("**<script>alert(1)</script>** and `<b>`")
    assert "<script>" not in rendered
    assert "&lt;script&gt;" in rendered


def test_the_web_deletion_page_offers_a_form(client):
    body = client.get("/account/delete").get_data(as_text=True)
    assert 'name="email"' in body and 'name="password"' in body
    assert "Settings" in body  # and the in-app route, for Google accounts


def test_a_wrong_password_on_the_web_keeps_the_account(app, client):
    with app.app_context():
        alice = _user("alice@example.com")
    wrong = client.post("/account/delete",
                        data={"email": "alice@example.com", "password": "nope"})
    unknown = client.post("/account/delete",
                          data={"email": "nobody@example.com", "password": "x"})
    assert wrong.status_code == unknown.status_code == 400
    # The same words either way, so the form never confirms an address exists.
    assert (wrong.get_data(as_text=True).split('class="error">')[1][:60]
            == unknown.get_data(as_text=True).split('class="error">')[1][:60])
    with app.app_context():
        assert db.session.get(User, alice) is not None


def test_the_right_password_on_the_web_deletes_the_account(app, client):
    with app.app_context():
        alice = _user("alice@example.com")
        _seed(alice, "alice@example.com")
    response = client.post(
        "/account/delete",
        data={"email": "ALICE@example.com", "password": PASSWORD},
    )
    assert response.status_code == 200
    assert "has been deleted" in response.get_data(as_text=True)
    with app.app_context():
        assert db.session.get(User, alice) is None
        assert not any(_owned_counts(alice).values())


# ── reporting advisor answers ────────────────────────────────────────────────

def test_an_advisor_answer_can_be_reported(app, client):
    response = client.post("/api/advisor/report", json={
        "answer": "Spray 5 litres of Mancozeb per acre at flowering.",
        "question": "What do I spray?",
        "reason": "harmful",
        "note": "That dose is ten times the label.",
    })
    assert response.status_code == 201, response.get_json()
    with app.app_context():
        report = AdvisorReport.query.one()
        assert report.reason == "harmful"
        assert report.question == "What do I spray?"
        assert report.model  # which model gave the answer is recorded


@pytest.mark.parametrize("payload", [
    {"answer": "", "reason": "harmful"},
    {"answer": "text", "reason": "because"},
    {"reason": "harmful"},
])
def test_a_report_needs_an_answer_and_a_known_reason(client, payload):
    assert client.post("/api/advisor/report", json=payload).status_code == 400
