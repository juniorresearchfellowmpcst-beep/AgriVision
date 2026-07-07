from flask import Flask
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from app.core.config import Config
from app.core.database import db
from app.api.routes.auth_routes import auth_bp

jwt = JWTManager()


def create_app():
    app = Flask(__name__)

    app.config.from_object(Config)

    CORS(app)
    app.register_blueprint(auth_bp, url_prefix="/api/auth")
    db.init_app(app)
    jwt.init_app(app)

    with app.app_context():
        db.create_all()

    return app