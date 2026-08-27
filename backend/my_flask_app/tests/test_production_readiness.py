"""The things that only matter once this stops being a laptop.

Each test here stands for a specific way a deployment goes wrong quietly:
shipping with the development signing key, returning an HTML error page to a
JSON client, answering a health probe with a lie, or letting an unauthenticated
endpoint be hammered. None of them show up in normal use, which is exactly why
they need tests.
"""

import importlib

import pytest

from app import create_app
from app.core import config as config_module
from app.core.config import Config
from app.core.database import db
from app.core.observability import REQUEST_ID_HEADER
from app.core.ratelimit import reset_all


@pytest.fixture()
def app(tmp_path_factory):
    application = create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret",
    })
    application.instance_path = str(tmp_path_factory.mktemp("instance"))
    with application.app_context():
        db.create_all()
    return application


@pytest.fixture()
def client(app):
    with app.test_client() as test_client:
        yield test_client


def _reload_config(monkeypatch, **env):
    """Re-import Config with a given environment, the way a boot would see it."""
    for key, value in env.items():
        if value is None:
            monkeypatch.delenv(key, raising=False)
        else:
            monkeypatch.setenv(key, value)
    return importlib.reload(config_module)


@pytest.fixture(autouse=True)
def _restore_config():
    """Reloading the config module mutates a global; put it back."""
    yield
    importlib.reload(config_module)


# ── refusing to start unsafely ───────────────────────────────────────────

def test_development_starts_with_no_configuration_at_all():
    """The convenient defaults must stay convenient."""
    assert Config.is_production() is False
    Config.check_production()  # must not raise


def test_production_refuses_the_development_signing_keys(monkeypatch):
    reloaded = _reload_config(
        monkeypatch,
        APP_ENV="production",
        SECRET_KEY=None,
        JWT_SECRET_KEY=None,
        DATABASE_URL="postgresql://user:pw@db/agrivision",
    )
    # Note: after a reload, reloaded.ConfigError is a *different* class object
    # from the one imported at the top of this file, so it has to be the one
    # matched against.
    with pytest.raises(reloaded.ConfigError) as excinfo:
        reloaded.Config.check_production()

    message = str(excinfo.value)
    assert "JWT_SECRET_KEY" in message
    assert "SECRET_KEY" in message
    # An error that does not say how to fix it costs someone an hour.
    assert "token_hex" in message


def test_production_reports_every_problem_at_once(monkeypatch):
    """One env var per restart is a miserable way to deploy."""
    reloaded = _reload_config(
        monkeypatch, APP_ENV="production", SECRET_KEY=None,
        JWT_SECRET_KEY=None, DATABASE_URL=None, ALLOW_SQLITE=None,
    )
    problems = reloaded.Config.production_problems()
    assert len(problems) == 3
    assert any("DATABASE_URL" in p for p in problems)


def test_ephemeral_sqlite_can_be_accepted_deliberately(monkeypatch):
    """A ground-station box with a real disk is a legitimate SQLite home."""
    reloaded = _reload_config(
        monkeypatch,
        APP_ENV="production",
        SECRET_KEY="a" * 64,
        JWT_SECRET_KEY="b" * 64,
        DATABASE_URL=None,
        ALLOW_SQLITE="1",
    )
    reloaded.Config.check_production()  # must not raise


def test_a_properly_configured_production_deployment_starts(monkeypatch):
    reloaded = _reload_config(
        monkeypatch,
        APP_ENV="production",
        SECRET_KEY="a" * 64,
        JWT_SECRET_KEY="b" * 64,
        DATABASE_URL="postgresql://user:pw@db/agrivision",
    )
    reloaded.Config.check_production()
    assert reloaded.Config.is_production() is True
    # Production must not create tables behind the operator's back.
    assert reloaded.Config.AUTO_CREATE_TABLES is False


def test_postgres_urls_from_older_hosts_are_normalised(monkeypatch):
    reloaded = _reload_config(
        monkeypatch, DATABASE_URL="postgres://user:pw@db/agrivision"
    )
    assert reloaded.Config.SQLALCHEMY_DATABASE_URI.startswith("postgresql://")


# ── errors the app can actually read ─────────────────────────────────────

def test_an_unknown_endpoint_answers_json_not_html(client):
    """Dio parses JSON; an HTML 404 becomes a useless 'Network error'."""
    response = client.get("/api/does-not-exist")
    assert response.status_code == 404
    assert response.mimetype == "application/json"

    body = response.get_json()
    assert body["status"] == "error"
    assert "/api/does-not-exist" in body["message"]


def test_the_wrong_verb_answers_json(client):
    response = client.get("/api/auth/signin")
    assert response.status_code == 405
    assert response.get_json()["status"] == "error"


def test_an_oversized_upload_is_refused_with_the_limit_named(app):
    app.config["MAX_CONTENT_LENGTH"] = 1024
    with app.test_client() as client:
        response = client.post(
            "/api/fieldscan/analyze",
            data={"file": (__import__("io").BytesIO(b"x" * 4096), "big.jpg")},
            content_type="multipart/form-data",
        )
    assert response.status_code == 413
    body = response.get_json()
    assert body["status"] == "error"
    assert "too large" in body["message"]


def test_every_response_carries_a_request_id(client):
    response = client.get("/healthz")
    assert response.headers[REQUEST_ID_HEADER]


def test_an_inbound_request_id_is_kept(client):
    """A trace started upstream must not be renamed here."""
    response = client.get("/healthz", headers={REQUEST_ID_HEADER: "abc123"})
    assert response.headers[REQUEST_ID_HEADER] == "abc123"


def test_an_error_body_quotes_the_request_id(client):
    response = client.get("/api/nope", headers={REQUEST_ID_HEADER: "trace-me"})
    assert response.get_json()["request_id"] == "trace-me"


# ── health probes ────────────────────────────────────────────────────────

def test_liveness_does_not_depend_on_anything(client):
    """A restart mid-flight because a camera is unplugged would be a disaster."""
    body = client.get("/healthz").get_json()
    assert body["status"] == "ok"


def test_readiness_checks_the_database(client):
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.get_json()["ready"] is True


def test_readiness_fails_when_the_database_is_gone(app, monkeypatch):
    from app.core.database import db as database

    def _explode(*_args, **_kwargs):
        raise RuntimeError("connection refused")

    monkeypatch.setattr(database.session, "execute", _explode)
    with app.test_client() as client:
        response = client.get("/readyz")

    assert response.status_code == 503
    assert response.get_json()["ready"] is False


# ── throttling the endpoints where guessing pays ─────────────────────────

@pytest.fixture()
def throttled_client(tmp_path_factory):
    reset_all()
    application = create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret",
        "RATELIMIT_ENABLED": True,
        "RATELIMIT_SIGNIN": 3,
        "RATELIMIT_WINDOW_S": 300,
    })
    application.instance_path = str(tmp_path_factory.mktemp("instance"))
    with application.app_context():
        db.create_all()
    with application.test_client() as test_client:
        yield test_client
    reset_all()


def test_repeated_signin_attempts_are_throttled(throttled_client):
    attempt = {"email": "nobody@example.com", "password": "wrong"}
    for _ in range(3):
        assert throttled_client.post("/api/auth/signin", json=attempt).status_code != 429

    response = throttled_client.post("/api/auth/signin", json=attempt)
    assert response.status_code == 429
    assert response.headers["Retry-After"]
    # The message must not reveal whether the account exists.
    message = response.get_json()["message"].lower()
    assert "too many attempts" in message
    assert "password" not in message and "email" not in message


def test_the_throttle_is_per_endpoint_group(throttled_client):
    """Being locked out of sign-in must not lock you out of signing up."""
    for _ in range(4):
        throttled_client.post(
            "/api/auth/signin", json={"email": "a@b.com", "password": "x"}
        )

    response = throttled_client.post(
        "/api/auth/signup",
        json={"name": "New", "email": "new@example.com", "password": "Str0ngPass!"},
    )
    assert response.status_code != 429


def test_the_throttle_is_off_by_default_under_testing(client):
    """Otherwise every suite in this repo fails for the wrong reason."""
    for _ in range(20):
        response = client.post(
            "/api/auth/signin", json={"email": "a@b.com", "password": "x"}
        )
        assert response.status_code != 429


# ── requiring a real token ───────────────────────────────────────────────

@pytest.fixture()
def strict_client(tmp_path_factory):
    """A deployment that refuses anonymous calls."""
    application = create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret",
        "REQUIRE_AUTH": True,
    })
    application.instance_path = str(tmp_path_factory.mktemp("instance"))
    with application.app_context():
        db.create_all()
    with application.test_client() as test_client:
        yield test_client


def test_lenient_endpoints_stay_open_by_default(client):
    """The field-network default: fly before anyone has signed in."""
    assert client.get("/api/capture/cameras").status_code == 200


def test_require_auth_refuses_an_anonymous_call(strict_client):
    response = strict_client.get("/api/capture/cameras")
    assert response.status_code == 401
    body = response.get_json()
    assert body["status"] == "error"
    assert "sign in" in body["message"].lower()


def test_require_auth_refuses_a_junk_token(strict_client):
    response = strict_client.get(
        "/api/capture/cameras",
        headers={"Authorization": "Bearer not-a-real-token"},
    )
    assert response.status_code == 401
    # An expired session is the common case, so say so rather than "invalid
    # token", which tells an operator nothing they can act on.
    assert "expired" in response.get_json()["message"].lower()


def test_require_auth_lets_a_signed_in_user_through(strict_client):
    signup = strict_client.post(
        "/api/auth/signup",
        json={"name": "Pilot", "email": "pilot@example.com", "password": "Str0ngPass!"},
    )
    assert signup.status_code in (200, 201), signup.get_json()

    # Signup registers but does not issue a token; the app signs in next.
    signin = strict_client.post(
        "/api/auth/signin",
        json={"email": "pilot@example.com", "password": "Str0ngPass!"},
    )
    assert signin.status_code == 200, signin.get_json()

    body = signin.get_json()
    token = body.get("token") or body.get("access_token")
    assert token, f"signin returned no token: {body}"

    response = strict_client.get(
        "/api/capture/cameras",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200


def test_health_probes_stay_open_under_require_auth(strict_client):
    """A load balancer has no token, and must still be able to ask."""
    assert strict_client.get("/healthz").status_code == 200
    assert strict_client.get("/readyz").status_code == 200
