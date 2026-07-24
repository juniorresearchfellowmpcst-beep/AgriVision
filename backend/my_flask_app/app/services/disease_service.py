"""Service layer for plant-leaf disease identification.

Thin orchestration over :class:`app.ai.disease_detector.DiseaseDetector`,
returning ``(response_dict, status_code)`` like the other services so the route
stays a dumb controller.
"""

from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

from app.ai import model_loader
from app.ai.disease_detector import DiseaseDetector
from app.ai.knowledge_base import all_condition_ids

# Reject absurdly large uploads outright (bytes). Phone photos are a few MB.
_MAX_UPLOAD_BYTES = 12 * 1024 * 1024


class DiseaseService:

    @staticmethod
    def capabilities() -> Tuple[Dict[str, Any], int]:
        """Report what the module can do and whether a trained model is active."""
        return {
            "status": "ok",
            "feature": "plant-disease-identification",
            "engine": "model" if model_loader.is_available() else "heuristic",
            "conditions": all_condition_ids(),
        }, 200

    @staticmethod
    def identify(
        image_bytes: bytes,
        filename: Optional[str] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Run disease detection on one uploaded leaf photo."""
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
        return result, 200
