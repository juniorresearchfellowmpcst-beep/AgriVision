from flask import Flask
from app.core.database import db
from app.core.config import Config

def create_app():

    app = Flask(__name__)
    app.config.from_object(Config)

    db.init_app(app)

    return app