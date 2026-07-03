from urllib import response

from flask import Blueprint
from flask import request
from flask import jsonify 

from app.services.auth_service import AuthService

auth_bp = Blueprint("auth",__name__)

@auth_bp.route("/signup",methods=["POST"])
def signup():
    
    data = request.get_json()
   
    response, status = AuthService.signup(
        data["name"],
        data["email"],
        data["password"],
    )

    return jsonify(response), status 

@auth_bp.route("/signin",methods=["POST"])
def signin():

    data = request.get_json()

    response, status = AuthService.signin(
        data["email"],
        data["password"]
    )

    return jsonify(response), status