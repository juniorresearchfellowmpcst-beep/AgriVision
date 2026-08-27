"""HTTP routes for the crop catalogue and the phone-camera scan.

Thin controllers over :class:`app.services.crop_service.CropService`.

    GET  /api/crops                            the picker grid
    GET  /api/crops/<crop_id>                  one crop: diseases + treatments
    GET  /api/crops/<crop_id>/diseases/<id>    one disease in full
    GET  /api/crops/<crop_id>/weeds            that crop's usual weeds
    GET  /api/crops/weeds                      every weed the app knows
    POST /api/crops/scan                       a phone photo -> diagnosis + treatment

``/scan`` is the drone-free path: no aircraft, no session, no prescription --
one photo, one crop, one answer. It is deliberately a separate endpoint from
``/api/fieldscan/analyze`` even though the detector underneath is the same one,
because the two have different contracts: the field-scan endpoint belongs to a
flight and a session, and this one belongs to a farmer holding a phone.
"""

import os

from flask import Blueprint, current_app, jsonify, request

from app.core.jwt import current_user_id, jwt_optional_lenient
from app.services.crop_service import CropService

crop_bp = Blueprint("crops", __name__)

_OUTPUT_SUBDIR = "fieldscan"


def _output_base() -> str:
    path = os.path.join(current_app.instance_path, _OUTPUT_SUBDIR)
    os.makedirs(path, exist_ok=True)
    return path


def _url_prefix() -> str:
    return request.host_url.rstrip("/") + "/api/fieldscan/file"


def _first_upload() -> tuple:
    """(bytes, filename) for the first non-empty file part, field-name agnostic."""
    for _field, storage in request.files.items(multi=True):
        data = storage.read()
        if data:
            return data, storage.filename
    return None, None


@crop_bp.route("", methods=["GET"])
@crop_bp.route("/", methods=["GET"])
def catalog():
    """Every crop the app can scan, plus the Weeds tile.

    Query: ``month`` (1-12) to mark and sort by what is in season.
    """
    try:
        month = int(request.args["month"]) if "month" in request.args else None
    except (TypeError, ValueError):
        month = None
    if month is not None and not 1 <= month <= 12:
        month = None

    response, status = CropService.catalog(month=month)
    return jsonify(response), status


@crop_bp.route("/weeds", methods=["GET"])
def weeds():
    """Every weed, or one crop's usual suspects via ``?crop=wheat``."""
    response, status = CropService.weed_catalog(request.args.get("crop"))
    return jsonify(response), status


@crop_bp.route("/scan", methods=["POST"])
@jwt_optional_lenient
def scan():
    """Diagnose a photo taken with the phone.

    Multipart: one image part (any field name), plus optional form fields
    ``crop``, ``mode`` (``disease`` | ``weed`` | ``both``), ``field_name``,
    ``lat``, ``lon``.
    """
    image_bytes, filename = _first_upload()
    if image_bytes is None:
        return jsonify({
            "status": "error",
            "message": "Attach a photo of the plant (multipart file part).",
        }), 400

    def _number(name):
        value = request.form.get(name)
        try:
            return float(value) if value not in (None, "") else None
        except (TypeError, ValueError):
            return None

    response, status = CropService.scan(
        image_bytes,
        crop=request.form.get("crop") or None,
        output_base=_output_base(),
        url_prefix=_url_prefix(),
        mode=request.form.get("mode") or "both",
        filename=filename,
        user_id=current_user_id(),
        field_name=request.form.get("field_name") or None,
        lat=_number("lat"),
        lon=_number("lon"),
    )
    return jsonify(response), status


# Registered after /weeds and /scan so those literal paths are matched first;
# Flask's routing would otherwise let "weeds" fall into <crop_id>.
@crop_bp.route("/<crop_id>", methods=["GET"])
def crop_detail(crop_id):
    """One crop: every disease it gets here, each with its treatment."""
    response, status = CropService.crop_detail(crop_id)
    return jsonify(response), status


@crop_bp.route("/<crop_id>/weeds", methods=["GET"])
def crop_weeds(crop_id):
    response, status = CropService.weed_catalog(crop_id)
    return jsonify(response), status


@crop_bp.route("/<crop_id>/diseases/<disease_id>", methods=["GET"])
def disease_detail(crop_id, disease_id):
    """One disease in full — the screen the farmer reads before spraying."""
    response, status = CropService.disease_detail(crop_id, disease_id)
    return jsonify(response), status
