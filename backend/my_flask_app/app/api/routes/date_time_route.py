from flask import Blueprint, jsonify

from app.services.dateandtime import TimeService

time_bp = Blueprint("time", __name__)


@time_bp.route("/now", methods=["GET"])
def get_time():
    return jsonify(TimeService.payload()), 200
