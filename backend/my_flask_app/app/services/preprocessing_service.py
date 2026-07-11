"""Service layer for multispectral preprocessing.

Bridges the HTTP layer and the `app.preprocessing` package. Like the other
services, methods are static and return a (response_dict, status_code) tuple.
Input here is server-side file paths (a drone capture is a folder of band
files), which keeps large binary uploads out of the JSON API.
"""

import os
import uuid
from typing import Dict, List, Optional, Tuple

from werkzeug.utils import secure_filename

from app.preprocessing import (
    PipelineConfig,
    analyze_images,
    available_indices,
    list_indices,
    odm_available,
    preprocess_capture,
    stitch_mosaic,
)
from app.preprocessing.config import DEFAULT_BANDS, DEFAULT_PANEL_REFLECTANCE
from app.preprocessing.io import discover_capture


def _build_config(payload: Dict) -> PipelineConfig:
    """Translate a JSON payload into a PipelineConfig, applying overrides."""
    config = PipelineConfig()

    if payload.get("bands"):
        config.bands = list(payload["bands"])

    if payload.get("panel_reflectance"):
        config.panel.reflectance.update(payload["panel_reflectance"])

    if payload.get("panel_roi"):
        # {band: [x, y, w, h]} or {"all": [...]}
        config.panel.roi = {k: tuple(v) for k, v in payload["panel_roi"].items()}

    if payload.get("black_level"):
        config.sensor.black_level.update(payload["black_level"])

    align = payload.get("alignment") or {}
    if "reference_band" in align:
        config.alignment.reference_band = align["reference_band"]
    if "warp_mode" in align:
        config.alignment.warp_mode = align["warp_mode"]
    if "min_alignment_score" in align:
        config.alignment.min_alignment_score = float(align["min_alignment_score"])

    return config


def _save_files(files: List[Tuple[str, bytes]], directory: str) -> List[Tuple[str, str]]:
    """Write (filename, bytes) uploads to disk; return [(orig_name, path)]."""
    saved = []
    for i, (name, data) in enumerate(files):
        safe = secure_filename(name) or f"image_{i}.tif"
        path = os.path.join(directory, safe)
        with open(path, "wb") as fh:
            fh.write(data)
        saved.append((name, path))
    return saved


def _resolve_bands(
    saved: List[Tuple[str, str]], band_map: Optional[Dict[str, str]]
) -> Dict[str, str]:
    """Map saved uploads to bands, by explicit band_map or filename auto-detect.

    band_map is {band: original_filename}. Auto-detect reuses discover_capture's
    filename keyword matching (e.g. 'nir', 'red', '_5').
    """
    by_name = {name: path for name, path in saved}
    if band_map:
        resolved = {}
        for band, fname in band_map.items():
            # Match by exact name or basename.
            path = by_name.get(fname)
            if path is None:
                path = next(
                    (p for n, p in saved if os.path.basename(n) == os.path.basename(fname)),
                    None,
                )
            if path:
                resolved[band] = path
        if resolved:
            return resolved

    # Auto-detect from filenames in the uploads directory.
    if saved:
        directory = os.path.dirname(saved[0][1])
        return discover_capture(directory, DEFAULT_BANDS)
    return {}


def _urlify(result: Dict, base_dir: str, url_prefix: str) -> None:
    """Rewrite absolute output paths in the result to fetchable URLs in place."""

    def to_url(path):
        if not isinstance(path, str) or not path:
            return path
        try:
            rel = os.path.relpath(path, base_dir).replace(os.sep, "/")
        except ValueError:
            return path
        if rel.startswith(".."):
            return path
        return f"{url_prefix}/{rel}"

    outputs = result.get("outputs") or {}
    for key in ("false_color", "risk_map"):
        if outputs.get(key):
            outputs[key] = to_url(outputs[key])
    previews = outputs.get("index_previews") or {}
    outputs["index_previews"] = {k: to_url(v) for k, v in previews.items()}

    if result.get("risk", {}).get("risk_map"):
        result["risk"]["risk_map"] = to_url(result["risk"]["risk_map"])

    for entry in (result.get("indices") or {}).values():
        for key in ("preview", "tiff"):
            if entry.get(key):
                entry[key] = to_url(entry[key])


class PreprocessingService:
    @staticmethod
    def capabilities() -> tuple:
        """Report what the module can do in this deployment."""
        return {
            "module": "multispectral-preprocessing",
            "default_bands": DEFAULT_BANDS,
            "default_panel_reflectance": DEFAULT_PANEL_REFLECTANCE,
            "steps": [
                "reflectance-calibration (panel, optional)",
                "band-alignment (ECC / ORB)",
                "alignment-quality-check",
                "vegetation-indices (full registry)",
                "risk-zoning (high / medium / low)",
                "field-report + action-plan",
                "mosaic-stitching",
            ],
            "indices": [s["key"] for s in list_indices()],
            "index_catalog": list_indices(),
            "orthomosaic_engine": odm_available() or "opencv-stitch-only",
        }, 200

    @staticmethod
    def analyze_images(
        files: List[Tuple[str, bytes]],
        panel_files: List[Tuple[str, bytes]],
        band_map: Optional[Dict[str, str]],
        calibrate: bool,
        indices: Optional[List[str]],
        primary_index: Optional[str],
        base_output_dir: str,
        url_prefix: str,
    ) -> tuple:
        """Analyse a set of uploaded band images (no drone/KML needed).

        Saves the uploads under a per-job directory, resolves which file is
        which band (explicit `band_map` or filename auto-detect), runs the full
        index → risk → report → action-plan chain, and returns the report with
        generated previews rewritten as fetchable URLs.
        """
        if not files:
            return {"status": "error", "message": "No image files uploaded."}, 400

        job_id = uuid.uuid4().hex
        job_dir = os.path.join(base_output_dir, job_id)
        uploads_dir = os.path.join(job_dir, "uploads")
        os.makedirs(uploads_dir, exist_ok=True)

        # Persist uploads to disk (OpenCV reads from paths, not bytes).
        saved = _save_files(files, uploads_dir)
        band_paths = _resolve_bands(saved, band_map)
        if not band_paths:
            return {
                "status": "error",
                "message": "Could not tell which image is which band. Name files "
                           "with the band (e.g. *_nir.tif, *_red.tif) or send a "
                           "'band_map' mapping band -> filename.",
                "uploaded": [name for name, _ in saved],
            }, 400

        panel_paths = None
        if calibrate and panel_files:
            panel_dir = os.path.join(job_dir, "panel")
            os.makedirs(panel_dir, exist_ok=True)
            panel_saved = _save_files(panel_files, panel_dir)
            panel_paths = _resolve_bands(panel_saved, None)

        config = PipelineConfig()

        try:
            result = analyze_images(
                band_paths=band_paths,
                output_dir=job_dir,
                config=config,
                panel_paths=panel_paths,
                indices=indices,
                primary_index=primary_index,
                align=True,
            )
        except (FileNotFoundError, ValueError, KeyError) as exc:
            return {"status": "error", "message": str(exc)}, 400
        except Exception as exc:  # unexpected
            return {"status": "error", "message": f"Analysis failed: {exc}"}, 500

        # Rewrite generated file paths as URLs the client can fetch.
        _urlify(result, base_output_dir, url_prefix)
        result["job_id"] = job_id
        result["message"] = (
            "Analysis complete."
            if result.get("calibrated")
            else "Analysis complete (uncalibrated — relative index values; add a "
                 "panel photo for absolute reflectance)."
        )
        return result, 200

    @staticmethod
    def calibrate(
        band_paths: Dict[str, str],
        panel_paths: Dict[str, str],
        output_dir: str,
        payload: Optional[Dict] = None,
    ) -> tuple:
        """Run reflectance calibration + band alignment for one capture."""
        payload = payload or {}
        # [DATA FLOW] JSON payload -> PipelineConfig (bands, panel reflectance,
        # ROI, alignment knobs) consumed by the pipeline below.
        config = _build_config(payload)

        # Indices default to all three crop-monitoring indices unless the
        # caller narrows the list; zoning is opt-in (k, default index).
        indices = payload.get("indices", ["ndvi", "gndvi", "ndre"])
        zones = int(payload.get("zones", 0) or 0)
        zone_index = payload.get("zone_index", "ndvi")

        # [DATA FLOW] hand off to the pipeline spine; `report` comes back as a
        # JSON-safe dict (plus an in-memory array handle we strip below).
        try:
            report = preprocess_capture(
                band_paths=band_paths,
                panel_paths=panel_paths,
                output_dir=output_dir,
                config=config,
                scene_metadata=payload.get("scene_metadata"),
                panel_metadata=payload.get("panel_metadata"),
                indices=indices,
                zones=zones,
                zone_index=zone_index,
            )
        except (FileNotFoundError, ValueError, KeyError) as exc:
            return {"status": "error", "message": str(exc)}, 400
        except Exception as exc:  # unexpected: surface but don't leak internals
            return {"status": "error", "message": f"Preprocessing failed: {exc}"}, 500

        # Drop the in-memory array handle before serialising to JSON.
        report.pop("_aligned_stack", None)

        aligned = report.get("alignment", {}).get("aligned_cleanly")
        report["message"] = (
            "Capture preprocessed; bands aligned cleanly."
            if aligned
            else "Capture preprocessed, but band alignment is below the quality "
                 "threshold — inspect the false-colour preview."
        )
        return report, 200

    @staticmethod
    def mosaic(image_paths: list, output_path: str) -> tuple:
        """Stitch a list of (already calibrated) raster paths into a mosaic."""
        import os
        import cv2

        if not image_paths or len(image_paths) < 2:
            return {"status": "error", "message": "Provide at least two images."}, 400

        images = []
        for p in image_paths:
            img = cv2.imread(p, cv2.IMREAD_COLOR)
            if img is None:
                return {"status": "error", "message": f"Cannot read image: {p}"}, 400
            images.append(img)

        try:
            mosaic = stitch_mosaic(images)
        except (ValueError, RuntimeError) as exc:
            return {"status": "error", "message": str(exc)}, 400

        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        cv2.imwrite(output_path, mosaic)
        return {
            "status": "ok",
            "message": "Mosaic created.",
            "output": output_path,
            "size": [int(mosaic.shape[1]), int(mosaic.shape[0])],
            "note": "2-D feature mosaic, not georeferenced. Use an ODM engine "
                    "for survey-grade orthomosaics.",
        }, 200
