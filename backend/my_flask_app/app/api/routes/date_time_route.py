from flask import Blueprint, jsonify
from services.time_service import TimeService 

time_bp = Blueprint("time",__name__)

@time_bp.route("/api/time",method=["GET"])
def get_time():
    return jsonify(TimeService.payload()),200