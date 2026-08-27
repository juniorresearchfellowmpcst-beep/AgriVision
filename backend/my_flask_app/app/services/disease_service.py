"""Service layer for plant-leaf disease identification.

Thin orchestration over :class:`app.ai.disease_detector.DiseaseDetector`,
returning ``(response_dict, status_code)`` like the other services so the route
stays a dumb controller.

Every successful scan is persisted (see :class:`app.api.models.disease_scan.
DiseaseScan`) so a diagnosis becomes field history instead of vanishing when
the operator leaves the screen — knowing *when* a blight first showed up in a
block matters as much as knowing it is there now.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional, Tuple

from app.ai import model_loader
from app.ai.disease_detector import DiseaseDetector
from app.ai.knowledge_base import all_condition_ids
from app.api.models.disease_scan import DiseaseScan
from app.repositories.disease_scan_repository import DiseaseScanRepository

logger = logging.getLogger(__name__)

# Reject absurdly large uploads outright (bytes). Phone photos are a few MB.
_MAX_UPLOAD_BYTES = 12 * 1024 * 1024


class DiseaseService:

    @staticmethod
    def capabilities() -> Tuple[Dict[str, Any], int]:
        """Report what the module can do and whether a trained model is active."""
        info = model_loader.info()
        return {
            "status": "ok",
            "feature": "plant-disease-identification",
            "engine": info["engine"],
            "conditions": all_condition_ids(),
            # What the trained model actually is, when one is loaded. Lets the
            # app (and a curl during deployment) confirm the model is live and
            # which one, rather than inferring it from a diagnosis.
            "model": {
                "file": info["model_file"],
                "classes": info["classes"],
                "input_size": info["input_size"],
                "labels": model_loader.labels(),
            } if info["engine"] == "model" else None,
        }, 200

    @staticmethod
    def identify(
        image_bytes: bytes,
        filename: Optional[str] = None,
        user_id: Optional[int] = None,
        field_name: Optional[str] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Run disease detection on one uploaded leaf photo and record it."""
        if not image_bytes:
            return {
                "status": "error",
                "message": "No image received. Attach a photo of the plant leaf.",
            }, 400

        if len(image_bytes) > _MAX_UPLOAD_BYTES:
            return {
                "status": "error",
                "message": "Image is too large. Please upload a photo under 12 MB.",
            }, 400

        result = DiseaseDetector.detect(image_bytes)
        if result.get("status") != "ok":
            # Detector reported an unreadable image or similar.
            return result, 400

        if filename:
            result["filename"] = filename

        scan = DiseaseService._record_scan(
            result, filename=filename, user_id=user_id, field_name=field_name
        )
        if scan is not None:
            result["scan_id"] = scan.id
            result["created_at"] = (
                scan.created_at.isoformat() if scan.created_at else None
            )
        return result, 200

    # ── History ────────────────────────────────────────────────────────────

    @staticmethod
    def _record_scan(
        result: Dict[str, Any],
        filename: Optional[str],
        user_id: Optional[int],
        field_name: Optional[str],
    ) -> Optional[DiseaseScan]:
        """Persist a diagnosis. A storage failure must not fail the scan —
        the operator still gets their answer, we just lose the history row."""
        try:
            disease = result.get("disease") or {}
            severity = result.get("severity") or {}
            scan = DiseaseScan(
                user_id=user_id,
                condition_id=disease.get("id"),
                condition_name=disease.get("name"),
                severity=severity.get("level"),
                confidence=float(result.get("confidence") or 0.0),
                engine=result.get("source"),
                is_healthy=bool(result.get("is_healthy")),
                filename=filename,
                field_name=field_name,
                detail=json.dumps(result),
            )
            return DiseaseScanRepository.create(scan)
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Could not record disease scan: %s", exc)
            return None

    @staticmethod
    def list_scans(user_id: Optional[int] = None) -> Tuple[Dict[str, Any], int]:
        """Past scans, newest first, for the Disease tab's history list."""
        scans = DiseaseScanRepository.list_scans(user_id=user_id)
        return {
            "status": "ok",
            "scans": [s.to_dict() for s in scans],
            "unhealthy_count": sum(1 for s in scans if not s.is_healthy),
        }, 200

    @staticmethod
    def get_scan(scan_id: int, user_id: Optional[int] = None) -> Tuple[Dict[str, Any], int]:
        """One past scan with its full diagnosis, re-openable from history."""
        scan = DiseaseScanRepository.get_by_id(scan_id)
        if scan is None:
            return {"status": "error", "message": "Scan not found."}, 404
        if scan.user_id is not None and user_id is not None and scan.user_id != user_id:
            return {"status": "error", "message": "Not your scan."}, 403
        return {"status": "ok", "scan": scan.to_dict(include_detail=True)}, 200
