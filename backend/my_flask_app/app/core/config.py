import os 

class Config:
    SECRET_KEY = os.getenv("SECERET_KEY")
    SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    