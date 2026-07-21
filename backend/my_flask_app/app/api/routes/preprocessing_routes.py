"""HTTP routes for multispectral preprocessing.

Thin controllers: validate the request, delegate to PreprocessingService, and
return its (dict, status) result — mirroring auth_routes.py.

[DATA FLOW ENTRY] HTTP JSON -> this route -> PreprocessingService.calibrate
-> app.preprocessing.pipeline.preprocess_capture (the spine). See
docs/PREPROCESSING_DATAFLOW.md for the full picture.
"""

import json
import os

from flask import Blueprint, current_app, jsonify, request, send_from_directory
from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request

from app.services.analysis_service import AnalysisService
from app.services.preprocessing_service import PreprocessingService

preprocessing_bp = Blueprint("preprocessing", __name__)

# Where per-job analysis outputs (previews, risk maps) are written/served from.
_OUTPUT_SUBDIR = "analysis_outputs"


def _output_base() -> str:
    return os.path.join(current_app.instance_path, _OUTPUT_SUBDIR)


def _require_fields(data, fields):
    if not isinstance(data, dict):
        return "Request body must be JSON"
    missing = [f for f in fields if not data.get(f)]
    if missing:
        return f"Missing required field(s): {', '.join(missing)}"
    return None


def _collect_uploads(want_panel: bool):
    """Split request.files into (scene_files, panel_files) as [(name, bytes)].

    Any file part whose field name contains 'panel' is treated as a panel image;
    everything else is a scene band image. This is field-name agnostic so the
    frontend can post under 'images', 'file[]', etc.
    """
    scene, panel = [], []
    for field_name, storage in request.files.items(multi=True):
        data = storage.read()
        if not data:
            continue
        item = (storage.filename or field_name, data)
        if want_panel and "panel" in field_name.lower():
            panel.append(item)
        else:
            scene.append(item)
    return scene, panel


@preprocessing_bp.route("/health", methods=["GET"])
def health():
    """Report the module's capabilities and available orthomosaic engine."""
    response, status = PreprocessingService.capabilities()
    return jsonify(response), status


@preprocessing_bp.route("/calibrate", methods=["POST"])
def calibrate():
    """Reflectance-calibrate and band-align one capture.

    Expected JSON:
        {
          "band_paths":  {"blue": "...", "green": "...", ...},   # scene
          "panel_paths": {"blue": "...", "green": "...", ...},   # panel photo
          "output_dir":  "/path/to/output",
          "panel_reflectance": {"blue": 0.49, ...},   # optional
          "panel_roi":  {"all": [x, y, w, h]},        # optional
          "alignment":  {"reference_band": "green"},  # optional
          "scene_metadata": {...}, "panel_metadata": {...}  # optional
        }
    """
    data = request.get_json(silent=True)

    error = _require_fields(data, ["band_paths", "panel_paths", "output_dir"])
    if error:
        return jsonify({"status": "error", "message": error}), 400

    response, status = PreprocessingService.calibrate(
        band_paths=data["band_paths"],
        panel_paths=data["panel_paths"],
        output_dir=data["output_dir"],
        payload=data,
    )
    return jsonify(response), status


@preprocessing_bp.route("/analyze-images", methods=["POST"])
def analyze_images_route():
    """Analyse multispectral band images picked from the system.

    Multipart form-data:
      * file parts        — the band images (any field names; parts whose name
                            contains 'panel' are used for calibration).
      * band_map (opt)    — JSON {"nir": "img1.tif", "red": "img2.tif", ...};
                            omit to auto-detect the band from each filename.
      * calibrate (opt)   — "true" to use the panel images for reflectance.
      * indices (opt)     — JSON list of index keys; omit for all available.
      * primary_index (opt) — index the risk map is based on (default auto).

    Returns the report, risk zones, action plan, and preview image URLs.
    """
    calibrate = str(request.form.get("calibrate", "")).lower() in ("1", "true", "yes")
    scene_files, panel_files = _collect_uploads(want_panel=calibrate)

    if not scene_files:
        return jsonify({
            "status": "error",
            "message": "Attach at least one band image (multipart file part).",
        }), 400

    band_map = None
    if request.form.get("band_map"):
        try:
            band_map = json.loads(request.form["band_map"])
        except (ValueError, TypeError):
            return jsonify({"status": "error", "message": "band_map must be JSON."}), 400

    indices = None
    if request.form.get("indices"):
        try:
            indices = json.loads(request.form["indices"])
        except (ValueError, TypeError):
            return jsonify({"status": "error", "message": "indices must be a JSON list."}), 400

    # Build the absolute URL prefix so the client can fetch generated previews.
    url_prefix = request.host_url.rstrip("/") + "/api/preprocessing/output"

    response, status = PreprocessingService.analyze_images(
        files=scene_files,
        panel_files=panel_files,
        band_map=band_map,
        calibrate=calibrate,
        indices=indices,
        primary_index=request.form.get("primary_index"),
        base_output_dir=_output_base(),
        url_prefix=url_prefix,
    )

    # Persist successful runs so the Reports/Alerts tabs have history. Never
    # let a bookkeeping failure break the analysis the user just paid for.
    if status == 200:
        try:
            verify_jwt_in_request(optional=True)
            identity = get_jwt_identity()
            user_id = int(identity) if identity is not None else None
        except Exception:
            user_id = None
        try:
            record = AnalysisService.record_analysis(
                response,
                user_id=user_id,
                field_name=request.form.get("field_name"),
            )
            response["record_id"] = record.id
        except Exception as exc:
            current_app.logger.warning("Could not persist analysis: %s", exc)

    return jsonify(response), status


@preprocessing_bp.route("/output/<path:relpath>", methods=["GET"])
def output_file(relpath):
    """Serve a generated preview/risk-map file for a completed analysis job."""
    return send_from_directory(_output_base(), relpath)


@preprocessing_bp.route("/mosaic", methods=["POST"])
def mosaic():
    """Stitch a list of calibrated rasters into a single mosaic.

    Expected JSON: {"image_paths": ["...", "..."], "output_path": "..."}
    """
    data = request.get_json(silent=True)

    error = _require_fields(data, ["image_paths", "output_path"])
    if error:
        return jsonify({"status": "error", "message": error}), 400

    response, status = PreprocessingService.mosaic(
        image_paths=data["image_paths"],
        output_path=data["output_path"],
    )
    return jsonify(response), status
