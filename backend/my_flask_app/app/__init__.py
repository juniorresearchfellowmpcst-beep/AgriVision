import atexit
import logging

from dotenv import load_dotenv
from flask import Flask
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_migrate import Migrate
from werkzeug.middleware.proxy_fix import ProxyFix

from app.core.config import Config
from app.core.database import db
from app.core.observability import (
    configure_logging,
    register_error_handlers,
    register_health,
    register_request_tracing,
)

# Import the models package so create_all() sees every table (users, drones,
# missions, analysis history, alerts) regardless of route import order.
import app.api.models  # noqa: F401

from app.api.routes.auth_routes import auth_bp
from app.api.routes.preprocessing_routes import preprocessing_bp
from app.api.routes.mission_routes import mission_bp
from app.api.routes.drone_routes import drone_bp
from app.api.routes.analysis_routes import analysis_bp
from app.api.routes.user_routes import user_bp
from app.api.routes.date_time_route import time_bp
from app.api.routes.disease_routes import disease_bp
from app.api.routes.mavlink_routes import mavlink_bp
from app.api.routes.credential_routes import credential_bp
from app.api.routes.capture_routes import capture_bp
from app.api.routes.spray_routes import spray_bp
from app.api.routes.field_scan_routes import field_scan_bp
from app.api.routes.system_routes import system_bp
from app.api.routes.survey_routes import survey_bp
from app.api.routes.crop_routes import crop_bp
from app.api.routes.advisor_routes import advisor_bp

jwt = JWTManager()
migrate = Migrate()

logger = logging.getLogger(__name__)


def create_app(config_overrides=None):
    """Build the Flask app.

    ``config_overrides`` must be applied *here* rather than after the call.
    ``db.create_all()`` below binds the SQLAlchemy engine to whatever the URI
    says at that moment, and the engine is then cached for the app's lifetime —
    so a test that creates the app and only afterwards points the config at
    ``sqlite:///:memory:`` is still talking to the real development database,
    and its ``drop_all()`` deletes the developer's actual data.
    """
    # Load MAIL_* / GOOGLE_CLIENT_ID etc. from a local .env if present.
    load_dotenv()

    app = Flask(__name__)

    app.config.from_object(Config)
    if config_overrides:
        app.config.update(config_overrides)

    # A test suite signs the same account in dozens of times, which is exactly
    # the shape the throttle exists to stop. Off by default under TESTING so
    # unrelated tests are not throttled into confusing failures; a test that
    # is *about* the throttle turns it back on explicitly.
    if app.config.get("TESTING") and "RATELIMIT_ENABLED" not in (config_overrides or {}):
        app.config["RATELIMIT_ENABLED"] = False

    # Before anything else, and before anything is listening: a production
    # deployment still carrying development signing keys must not start.
    # Tests and explicit overrides opt out by not setting APP_ENV=production.
    if not app.config.get("TESTING"):
        Config.check_production()

    configure_logging(app)

    # X-Forwarded-* are only trustworthy when we know how many proxies set
    # them. Applied only when told, because trusting the header with nothing
    # in front of the app lets any client claim any source address — which
    # would hand the auth throttle a fresh quota per request.
    proxy_count = int(app.config.get("PROXY_COUNT", 0))
    if proxy_count > 0:
        app.wsgi_app = ProxyFix(
            app.wsgi_app, x_for=proxy_count, x_proto=proxy_count, x_host=proxy_count
        )

    # Browsers enforce CORS; the mobile app does not. An explicit allowlist
    # only matters for the Flutter web build served from another origin.
    origins = app.config.get("CORS_ORIGINS") or "*"
    CORS(app, origins=origins)

    app.register_blueprint(auth_bp, url_prefix="/api/auth")
    app.register_blueprint(preprocessing_bp, url_prefix="/api/preprocessing")
    app.register_blueprint(mission_bp, url_prefix="/api/mission")
    app.register_blueprint(drone_bp, url_prefix="/api/drones")
    app.register_blueprint(analysis_bp, url_prefix="/api/analysis")
    app.register_blueprint(user_bp, url_prefix="/api/users")
    app.register_blueprint(time_bp, url_prefix="/api/time")
    app.register_blueprint(disease_bp, url_prefix="/api/disease")
    app.register_blueprint(mavlink_bp, url_prefix="/api/mavlink")
    app.register_blueprint(credential_bp, url_prefix="/api/credentials")
    # Live camera capture -> K-means spray prescription -> weed/disease scan.
    app.register_blueprint(capture_bp, url_prefix="/api/capture")
    app.register_blueprint(spray_bp, url_prefix="/api/spray")
    app.register_blueprint(field_scan_bp, url_prefix="/api/fieldscan")
    app.register_blueprint(system_bp, url_prefix="/api/system")
    # The survey flight that ties the rest together: camera selection -> live
    # CNN scan -> crop-health summary and action plan -> K-means treatment map
    # -> an authorised, targeted spray.
    app.register_blueprint(survey_bp, url_prefix="/api/survey")
    # The crop picker and the phone-camera scan, which needs no aircraft.
    app.register_blueprint(crop_bp, url_prefix="/api/crops")
    # "More information": a photo and its diagnosis handed to Gemini.
    app.register_blueprint(advisor_bp, url_prefix="/api/advisor")

    db.init_app(app)
    jwt.init_app(app)
    # Wires `flask db migrate/upgrade`. The app runs fine without ever using
    # it; what it buys is a way to add a column later without hand-editing a
    # live database, which create_all() cannot do.
    migrate.init_app(app, db)

    register_request_tracing(app)
    register_error_handlers(app)
    register_health(app)

    if app.config.get("AUTO_CREATE_TABLES", True):
        with app.app_context():
            db.create_all()
    else:
        logger.info(
            "AUTO_CREATE_TABLES is off: the schema is expected to be managed "
            "with `flask db upgrade`."
        )

    _register_shutdown(app)

    return app


def _register_shutdown(app):
    """Let go of the hardware when the process ends.

    A camera left with an open RTSP session, or a flight controller left with
    a heartbeat that has stopped arriving, both take time to time out — long
    enough that an operator restarting the server sees the *next* start fail
    to connect and concludes the hardware is broken.
    """
    if app.config.get("TESTING"):
        return

    def _shutdown():
        try:
            from app.capture.live import hub
            from app.services.live_analysis import manager

            manager.shutdown()
            hub.shutdown()
        except Exception:  # pragma: no cover - best effort on the way out
            pass

    atexit.register(_shutdown)
