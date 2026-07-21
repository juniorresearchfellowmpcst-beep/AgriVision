from dotenv import load_dotenv
from flask import Flask
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from app.core.config import Config
from app.core.database import db

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

jwt = JWTManager()


def create_app():
    # Load MAIL_* / GOOGLE_CLIENT_ID etc. from a local .env if present.
    load_dotenv()

    app = Flask(__name__)

    app.config.from_object(Config)

    CORS(app)
    app.register_blueprint(auth_bp, url_prefix="/api/auth")
    app.register_blueprint(preprocessing_bp, url_prefix="/api/preprocessing")
    app.register_blueprint(mission_bp, url_prefix="/api/mission")
    app.register_blueprint(drone_bp, url_prefix="/api/drones")
    app.register_blueprint(analysis_bp, url_prefix="/api/analysis")
    app.register_blueprint(user_bp, url_prefix="/api/users")
    app.register_blueprint(time_bp, url_prefix="/api/time")
    db.init_app(app)
    jwt.init_app(app)

    with app.app_context():
        db.create_all()

    return app
