from flask import Flask
from app.core.config import Config
from app.core.database import db
from app.api.routes.auth_routes import auth_bp

def create_app():
    app = Flask(__name__)

    app.config.from_object(Config)

    print(app.config.get("SQLALCHEMY_DATABASE_URI"))  # Debug
    app.register_blueprint(auth_bp, url_prefix="/api/auth")
    db.init_app(app)

    return app