class Config:
    SECRET_KEY = "agrivision"
    JWT_SECRET_KEY = "agrivisionjwt"

    SQLALCHEMY_DATABASE_URI = "sqlite:///agrivision.db"
    SQLALCHEMY_TRACK_MODIFICATIONS = False

# This file is to configure the database and the JWT secret key for the application. 
# The Config class is used to store the configuration variables for the application. 
# The SECRET_KEY is used to sign the session cookies and the JWT_SECRET_KEY is used to sign the JWT tokens.
#  The SQLALCHEMY_DATABASE_URI is used to specify the database URI for SQLAlchemy and SQLALCHEMY_TRACK_MODIFICATIONS
#  is set to False to disable the modification tracking feature of SQLAlchemy.