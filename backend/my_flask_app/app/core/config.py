"""Configuration for the AgriVision backend.

One class, read once by the app factory. Everything is overridable by
environment variable, and the defaults are chosen so that ``python run.py`` on
a developer's laptop works with no setup at all.

The important rule here is that **development defaults must never silently
become production defaults**. A dev signing key that ships to a real
deployment lets anyone mint a token for any account, and the failure is
invisible — the app works perfectly right up until someone notices. So the
convenient defaults stay convenient, and :func:`Config.check_production`
refuses to start when ``APP_ENV=production`` and any of them is still in
place. Loud at boot beats silent forever.
"""

import os
from datetime import timedelta

# The stand-ins that must not survive into a real deployment.
DEV_SECRET_KEY = "agrivision-dev-secret-key-0123456789abcdef"
DEV_JWT_SECRET_KEY = "agrivision-dev-jwt-secret-0123456789abcdef"


def _flag(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


def _int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def _csv(name: str, default: str = "") -> list:
    raw = os.environ.get(name, default) or ""
    return [item.strip() for item in raw.split(",") if item.strip()]


class ConfigError(RuntimeError):
    """A deployment is configured in a way that cannot be allowed to run."""


class Config:
    # "development" or "production". Only this switch decides whether the
    # checks below are enforced — nothing infers it from the presence of a
    # DATABASE_URL or a PORT, because guessing here fails in the unsafe
    # direction.
    APP_ENV = os.environ.get("APP_ENV", "development").strip().lower()

    # >=32-byte keys silence PyJWT's InsecureKeyLengthWarning; override via env
    # in production. NOTE: changing these invalidates already-issued tokens,
    # so app users must sign in again after a key change.
    SECRET_KEY = os.environ.get("SECRET_KEY", DEV_SECRET_KEY)
    JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY", DEV_JWT_SECRET_KEY)

    # Long-lived tokens: the default 15-minute expiry constantly stranded the
    # mobile app with 401s once its stored token went stale. An operator in a
    # field with no signal cannot re-authenticate, so the token has to outlast
    # the flight by a wide margin.
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(days=_int("JWT_EXPIRES_DAYS", 30))

    # Use DATABASE_URL when provided (e.g. a Railway Postgres add-on); fall back
    # to a local SQLite file for development. WARNING: SQLite on a cloud host is
    # EPHEMERAL — the file lives on the container's disk and is wiped on every
    # redeploy/restart, so accounts, missions and analysis history vanish. For a
    # real deployment attach Postgres and set DATABASE_URL.
    _database_url = os.environ.get("DATABASE_URL", "sqlite:///agrivision.db")
    # SQLAlchemy 2.x rejects the legacy "postgres://" scheme some hosts still
    # emit; normalise it to "postgresql://".
    if _database_url.startswith("postgres://"):
        _database_url = _database_url.replace("postgres://", "postgresql://", 1)
    SQLALCHEMY_DATABASE_URI = _database_url
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # pool_pre_ping costs one cheap round trip per checkout and saves the class
    # of failure where a managed Postgres (or anything behind a NAT idle
    # timeout) has closed the connection while the ground station sat parked
    # between flights: without it the next request after the break dies on a
    # stale socket instead of transparently reconnecting.
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_recycle": _int("DB_POOL_RECYCLE_S", 1800),
    }

    # Hard ceiling on a request body, enforced by Flask before anything is
    # buffered. The field-scan service applies its own 16 MB image limit with a
    # friendlier message; this is the backstop that stops a malformed or
    # hostile upload from being read into memory at all.
    MAX_CONTENT_LENGTH = _int("MAX_UPLOAD_MB", 32) * 1024 * 1024

    # Browsers enforce CORS; the mobile app does not. This therefore only
    # matters when the Flutter *web* build is served from another origin.
    # Empty means "any origin", which is the right default for a ground
    # station on a closed field network and the wrong one for a public host.
    CORS_ORIGINS = _csv("CORS_ORIGINS")

    # Concurrent MJPEG viewers allowed per process. Each one holds a worker
    # thread for as long as it watches, so this must stay well under the
    # gunicorn thread count or a few phones can starve the flight-control
    # endpoints. See gunicorn.conf.py.
    LIVE_STREAM_MAX_VIEWERS = _int("LIVE_STREAM_MAX_VIEWERS", 8)

    # Refuse anonymous calls on the endpoints that currently tolerate them
    # (everything using `jwt_optional_lenient`). OFF by default, and that is a
    # product decision rather than laziness: on a closed field network the
    # operator registers cameras and flies before anyone signs in, and turning
    # this on makes the app unusable in that situation. Turn it on for a
    # backend reachable from the internet.
    REQUIRE_AUTH = _flag("REQUIRE_AUTH", False)

    # Sign-in / sign-up / password-reset throttle: attempts per IP per window.
    # Guards the password endpoints against credential stuffing without
    # locking out an operator who fat-fingers a password twice.
    RATELIMIT_ENABLED = _flag("RATELIMIT_ENABLED", True)
    RATELIMIT_WINDOW_S = _int("RATELIMIT_WINDOW_S", 300)
    RATELIMIT_SIGNIN = _int("RATELIMIT_SIGNIN", 10)
    RATELIMIT_SIGNUP = _int("RATELIMIT_SIGNUP", 5)
    RATELIMIT_PASSWORD_RESET = _int("RATELIMIT_PASSWORD_RESET", 5)

    # Number of reverse proxies in front of this app. Set to 1 behind Railway /
    # nginx / Cloudflare so request.remote_addr (which the throttle keys on)
    # and request.scheme come from X-Forwarded-*. Leave 0 when the app is
    # reached directly, otherwise any client can forge its own source address
    # by sending the header itself.
    PROXY_COUNT = _int("PROXY_COUNT", 0)

    # Create tables on boot. Right for development and for a single-box ground
    # station; wrong once there is a schema to migrate, because create_all()
    # only ever CREATEs — it never ALTERs an existing table, so a column added
    # later simply never appears and every query against it fails at runtime.
    # Production defaults to off: run `flask db upgrade` instead.
    AUTO_CREATE_TABLES = _flag(
        "AUTO_CREATE_TABLES",
        os.environ.get("APP_ENV", "development").strip().lower() != "production",
    )

    LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
    # JSON lines for a log aggregator; plain text for a human watching a
    # terminal at the edge of a field.
    LOG_JSON = _flag("LOG_JSON", False)

    # Default MAVLink endpoint used when /api/mavlink/connect is called without
    # a "url". "udpin:" means *we listen* — which is what a simulator (Mission
    # Planner SITL, MAVProxy --out, ArduPilot sim_vehicle.py) streams into.
    # Real hardware over a USB radio would be e.g. "COM5" or "/dev/ttyUSB0".
    MAVLINK_URL = os.environ.get("MAVLINK_URL", "udpin:0.0.0.0:14550")

    # Our address on the MAVLink network. Change to 254 when Mission Planner
    # or QGroundControl watches the same vehicle — they also default to 255,
    # and two ground stations sharing an id corrupt mission uploads.
    MAVLINK_SOURCE_SYSTEM = os.environ.get("MAVLINK_SOURCE_SYSTEM", "255")

    # Google Gemini, behind the app's "More information" button: a scan photo
    # and the CNN's diagnosis are sent up and the farmer can keep asking
    # questions about them. UNSET BY DEFAULT AND OPTIONAL — every other feature
    # in this app runs on a field network with no internet at all, and this is
    # the one that cannot. With no key the endpoints answer 503 with a clear
    # message and the app hides the button, rather than the button existing and
    # failing when someone taps it.
    #
    # NOTE: this is the one place where a field photograph leaves the ground
    # station. It is opt-in for exactly that reason.
    GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
    GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")

    # ── boot checks ───────────────────────────────────────────────────────

    @classmethod
    def is_production(cls) -> bool:
        return cls.APP_ENV == "production"

    @classmethod
    def production_problems(cls) -> list:
        """Everything about this deployment that must be fixed before it runs.

        Returned rather than raised so the caller can report all of them at
        once — fixing one env var per restart is a miserable way to deploy.
        """
        problems = []

        if cls.SECRET_KEY == DEV_SECRET_KEY:
            problems.append(
                "SECRET_KEY is still the development default. Generate one "
                "with: python -c \"import secrets; print(secrets.token_hex(32))\""
            )
        if cls.JWT_SECRET_KEY == DEV_JWT_SECRET_KEY:
            problems.append(
                "JWT_SECRET_KEY is still the development default. Anyone who "
                "has read this repository could sign a token for any account. "
                "Generate one with: python -c \"import secrets; "
                "print(secrets.token_hex(32))\""
            )
        if cls.SQLALCHEMY_DATABASE_URI.startswith("sqlite"):
            problems.append(
                "DATABASE_URL is unset, so the app would use a local SQLite "
                "file. On a container host that file is wiped on every "
                "redeploy, taking every account, mission and scan with it. "
                "Attach Postgres and set DATABASE_URL. (If this really is a "
                "single ground-station box with a persistent disk, set "
                "ALLOW_SQLITE=1 to accept it.)"
            )

        return problems

    @classmethod
    def check_production(cls) -> None:
        """Refuse to start a production deployment that is unsafe.

        Raises :class:`ConfigError` listing every problem found.
        """
        if not cls.is_production():
            return

        problems = cls.production_problems()
        if _flag("ALLOW_SQLITE"):
            problems = [p for p in problems if not p.startswith("DATABASE_URL")]
        if not problems:
            return

        raise ConfigError(
            "APP_ENV=production, but this deployment is not safe to start:\n"
            + "\n".join(f"  * {problem}" for problem in problems)
            + "\n\nFix the above, or run with APP_ENV=development to use the "
            "development defaults knowingly."
        )
