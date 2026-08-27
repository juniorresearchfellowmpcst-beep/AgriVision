"""HTTP routes for a survey flight.

Thin controllers over :class:`app.services.survey_service.SurveyService`.

    GET    /api/survey/capabilities        which camera modes this rig can fly
    GET    /api/survey/runs                past runs, newest first
    POST   /api/survey/runs                start a run (camera mode + crop)
    GET    /api/survey/runs/<id>           live status while it flies
    POST   /api/survey/runs/<id>/shoot     trigger the cameras, filed to this run
    POST   /api/survey/runs/<id>/finish    end the pass and summarise it
    GET    /api/survey/runs/<id>/summary   re-open a finished run
    POST   /api/survey/runs/<id>/authorise tank confirmed + permission -> spray
    POST   /api/survey/runs/<id>/cancel    abandon the run

The one route that can open a valve is ``/authorise``, and it needs three
separate things in its body: the tank confirmed filled, spraying authorised,
and ``start: true``. That is not ceremony -- each is a different mistake to
make, and collapsing them into one flag would make all three easy to make at
once.
"""

import os

from flask import Blueprint, current_app, jsonify, request

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.survey_service import SurveyService

survey_bp = Blueprint("survey", __name__)

_CAPTURE_SUBDIR = "captures"
_OUTPUT_SUBDIR = "spray"


def _capture_base() -> str:
    path = os.path.join(current_app.instance_path, _CAPTURE_SUBDIR)
    os.makedirs(path, exist_ok=True)
    return path


def _output_base() -> str:
    path = os.path.join(current_app.instance_path, _OUTPUT_SUBDIR)
    os.makedirs(path, exist_ok=True)
    return path


def _capture_url_prefix() -> str:
    return request.host_url.rstrip("/") + "/api/capture/file"


def _spray_url_prefix() -> str:
    return request.host_url.rstrip("/") + "/api/spray/output"


@survey_bp.route("/capabilities", methods=["GET"])
@jwt_optional_lenient
def capabilities():
    """Which camera modes are flyable, and why the others are not."""
    response, status = SurveyService.capabilities(user_id=current_user_id())
    return jsonify(response), status


@survey_bp.route("/runs", methods=["GET"])
@jwt_optional_lenient
def list_runs():
    response, status = SurveyService.list_runs(user_id=current_user_id())
    return jsonify(response), status


@survey_bp.route("/runs", methods=["POST"])
@jwt_optional_lenient
def start_run():
    """Start a survey.

    JSON: ``{"camera_mode": "rgb"|"multispectral"|"both",
    "detection_target": "disease"|"weed"|"both", "crop": "soybean",
    "field_name": "Block A", "rgb_camera_id": 1}``
    """
    response, status = SurveyService.start(
        request.get_json(silent=True), user_id=current_user_id()
    )
    return jsonify(response), status


@survey_bp.route("/runs/<int:run_id>", methods=["GET"])
@jwt_optional_lenient
def run_status(run_id):
    """The rolling readout while the aircraft is over the field."""
    response, status = SurveyService.status(run_id, user_id=current_user_id())
    return jsonify(response), status


@survey_bp.route("/runs/<int:run_id>/shoot", methods=["POST"])
@jwt_optional_lenient
def shoot(run_id):
    """Trigger every enabled camera once, filed under this run's session."""
    response, status = SurveyService.shoot(
        run_id,
        base_dir=_capture_base(),
        url_prefix=_capture_url_prefix(),
        payload=request.get_json(silent=True),
        user_id=current_user_id(),
    )
    return jsonify(response), status


@survey_bp.route("/runs/<int:run_id>/finish", methods=["POST"])
@jwt_optional_lenient
def finish(run_id):
    """End the pass: crop health, action plan, tank plan and treatment map."""
    response, status = SurveyService.finish(
        run_id,
        capture_base=_capture_base(),
        output_base=_output_base(),
        url_prefix=_spray_url_prefix(),
        payload=request.get_json(silent=True),
        user_id=current_user_id(),
    )
    return jsonify(response), status


@survey_bp.route("/runs/<int:run_id>/summary", methods=["GET"])
@jwt_optional_lenient
def summary(run_id):
    response, status = SurveyService.summary(run_id, user_id=current_user_id())
    return jsonify(response), status


@survey_bp.route("/runs/<int:run_id>/authorise", methods=["POST"])
@survey_bp.route("/runs/<int:run_id>/authorize", methods=["POST"])
@jwt_optional_lenient
def authorise(run_id):
    """Record the tank and the permission, then send the spray mission.

    JSON: ``{"tank_filled": true, "tank_litres": 10, "tank_product": "...",
    "authorised_by": "name", "option": "severe_only", "start": true}``

    Both spellings of the path are routed: the app is written in one and half
    the field notes in the other, and a 404 over an -ise/-ize is a bad reason
    for a farmer to be unable to spray.
    """
    response, status = SurveyService.authorise(
        run_id, request.get_json(silent=True), user_id=current_user_id()
    )
    return jsonify(response), status


@survey_bp.route("/runs/<int:run_id>/cancel", methods=["POST"])
@jwt_optional_lenient
def cancel(run_id):
    response, status = SurveyService.cancel(run_id, user_id=current_user_id())
    return jsonify(response), status
