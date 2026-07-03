class Config:
    SECRET_KEY = "agrivision"
    JWT_SECRET_KEY = "agrivisionjwt"

    SQLALCHEMY_DATABASE_URI = "sqlite:///agrivision.db"
    SQLALCHEMY_TRACK_MODIFICATIONS = False