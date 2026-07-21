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

    SQLALCHEMY_DATABASE_URI = "sqlite:///agrivision.db"
    SQLALCHEMY_TRACK_MODIFICATIONS = False

# This file is to configure the database and the JWT secret key for the application.
# The Config class is used to store the configuration variables for the application.
# The SECRET_KEY is used to sign the session cookies and the JWT_SECRET_KEY is used to sign the JWT tokens.
#  The SQLALCHEMY_DATABASE_URI is used to specify the database URI for SQLAlchemy and SQLALCHEMY_TRACK_MODIFICATIONS
#  is set to False to disable the modification tracking feature of SQLAlchemy.
