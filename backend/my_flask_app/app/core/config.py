import os
from datetime import timedelta


class Config:
    # >=32-byte keys silence PyJWT's InsecureKeyLengthWarning; override via env
    # in production. NOTE: changing these invalidates already-issued tokens,
    # so app users must sign in again after a key change.
    SECRET_KEY = os.environ.get(
        "SECRET_KEY", "agrivision-dev-secret-key-0123456789abcdef"
    )
    JWT_SECRET_KEY = os.environ.get(
        "JWT_SECRET_KEY", "agrivision-dev-jwt-secret-0123456789abcdef"
    )

    # Long-lived dev tokens: the default 15-minute expiry constantly stranded
    # the mobile app with 401s once its stored token went stale.
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(days=30)

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

    # Default MAVLink endpoint used when /api/mavlink/connect is called without
    # a "url". "udpin:" means *we listen* — which is what a simulator (Mission
    # Planner SITL, MAVProxy --out, ArduPilot sim_vehicle.py) streams into.
    # Real hardware over a USB radio would be e.g. "COM5" or "/dev/ttyUSB0".
    MAVLINK_URL = os.environ.get("MAVLINK_URL", "udpin:0.0.0.0:14550")

    # Our address on the MAVLink network. Change to 254 when Mission Planner
    # or QGroundControl watches the same vehicle — they also default to 255,
    # and two ground stations sharing an id corrupt mission uploads.
    MAVLINK_SOURCE_SYSTEM = os.environ.get("MAVLINK_SOURCE_SYSTEM", "255")

# This file is to configure the database and the JWT secret key for the application.
# The Config class is used to store the configuration variables for the application.
# The SECRET_KEY is used to sign the session cookies and the JWT_SECRET_KEY is used to sign the JWT tokens.
#  The SQLALCHEMY_DATABASE_URI is used to specify the database URI for SQLAlchemy and SQLALCHEMY_TRACK_MODIFICATIONS
#  is set to False to disable the modification tracking feature of SQLAlchemy.
