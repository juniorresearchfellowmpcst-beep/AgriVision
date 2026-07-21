"""HTTP routes for analysis history: field reports + AI alerts.

Thin controllers over AnalysisService. All endpoints accept anonymous requests
(analyses can be run without a login) but scope to the user when a JWT is sent.
"""

from flask import Blueprint, jsonify, request

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.analysis_service import AnalysisService

analysis_bp = Blueprint("analysis", __name__)


@analysis_bp.route("/reports", methods=["GET"])
@jwt_optional_lenient
def list_reports():
    response, status = AnalysisService.list_reports(user_id=current_user_id())
    return jsonify(response), status


@analysis_bp.route("/reports/<int:record_id>", methods=["GET"])
@jwt_optional_lenient
def get_report(record_id):
    response, status = AnalysisService.get_report(
        record_id, user_id=current_user_id()
    )
    return jsonify(response), status


@analysis_bp.route("/alerts", methods=["GET"])
@jwt_optional_lenient
def list_alerts():
    include_resolved = (
        str(request.args.get("include_resolved", "")).lower() in ("1", "true", "yes")
    )
    response, status = AnalysisService.list_alerts(
        user_id=current_user_id(), active_only=not include_resolved
    )
    return jsonify(response), status


@analysis_bp.route("/alerts/<int:alert_id>/resolve", methods=["POST"])
@jwt_optional_lenient
def resolve_alert(alert_id):
    response, status = AnalysisService.resolve_alert(
        alert_id, user_id=current_user_id()
    )
    return jsonify(response), status
