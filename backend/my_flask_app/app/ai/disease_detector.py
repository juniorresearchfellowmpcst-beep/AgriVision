"""Plant-leaf disease identification from a single RGB photo.

Pipeline
--------
1. Decode the uploaded photo (:func:`app.ai.utils.decode_image`).
2. If an optional trained model is configured, use its label
   (:mod:`app.ai.model_loader`); otherwise classify from the colour/lesion
   features (:func:`app.ai.utils.extract_features`).
3. Look the resulting condition up in the knowledge base
   (:mod:`app.ai.knowledge_base`) and attach a severity estimate.

The public entry point is :func:`DiseaseDetector.detect`, which returns a plain
dict ready to be JSON-serialised by the service/route layers.
"""

from __future__ import annotations

from typing import Any, Dict, Optional

from app.ai import model_loader, utils
from app.ai.knowledge_base import get_condition

# Model labels may not match our ids exactly; normalise common variants.
_LABEL_ALIASES = {
    "healthy": "healthy",
    "leaf_spot": "fungal_leaf_spot",
    "bacterial_spot": "fungal_leaf_spot",
    "septoria": "fungal_leaf_spot",
    "cercospora": "fungal_leaf_spot",
    "early_blight": "blight",
    "late_blight": "blight",
    "blight": "blight",
    "powdery": "powdery_mildew",
    "powdery_mildew": "powdery_mildew",
    "mildew": "powdery_mildew",
    "rust": "fungal_leaf_spot",
    "nutrient": "nutrient_deficiency",
    "chlorosis": "nutrient_deficiency",
    "yellow": "nutrient_deficiency",
    "pest": "pest_damage",
}


class DiseaseDetector:
    """Stateless detector; all methods are static so it needs no wiring."""

    @staticmethod
    def detect(image_bytes: bytes) -> Dict[str, Any]:
        """Identify the likely leaf condition and attach treatment guidance.

        Returns a dict with ``status`` == ``"ok"`` on success, or ``"error"``
        with a ``message`` when the image can't be read.
        """
        img = utils.decode_image(image_bytes)
        if img is None:
            return {
                "status": "error",
                "message": "Could not read the image. Please upload a clear "
                "JPG or PNG photo of a single leaf.",
            }

        features = utils.extract_features(img)

        # Guard: if we couldn't find a leaf, ask for a better photo rather than
        # confidently reporting nonsense.
        if not features.get("leaf_found", False):
            payload = DiseaseDetector._build_payload(
                condition_id="general_stress",
                confidence=0.2,
                features=features,
                source="heuristic",
            )
            payload["message"] = (
                "Couldn't clearly detect a leaf. Fill more of the frame with a "
                "single, well-lit leaf against a plain background for a better "
                "result."
            )
            payload["low_confidence"] = True
            return payload

        # Prefer a trained model when one is configured; else use the heuristic.
        model_result = model_loader.predict(img)
        if model_result is not None:
            raw_label, confidence = model_result
            condition_id = DiseaseDetector._normalise_label(raw_label)
            source = "model"
        else:
            condition_id, confidence = DiseaseDetector._classify(features)
            source = "heuristic"

        payload = DiseaseDetector._build_payload(
            condition_id=condition_id,
            confidence=confidence,
            features=features,
            source=source,
        )
        return payload

    # ── classification ────────────────────────────────────────────────────────

    @staticmethod
    def _normalise_label(raw_label: str) -> str:
        key = str(raw_label).strip().lower().replace(" ", "_").replace("-", "_")
        if key in _LABEL_ALIASES:
            return _LABEL_ALIASES[key]
        # Substring match for compound labels like "tomato_late_blight".
        for token, cid in _LABEL_ALIASES.items():
            if token in key:
                return cid
        return key  # get_condition() falls back to general_stress if unknown

    @staticmethod
    def _classify(f: Dict[str, Any]) -> (str, float):
        """Rule-based classification from colour/lesion features.

        Returns ``(condition_id, confidence)``. Confidence is a calibrated-ish
        0..1 estimate reflecting how strongly the dominant symptom stands out;
        it is intentionally modest because a photo can only reveal a category.
        """
        green = f["green_fraction"]
        yellow = f["yellow_fraction"]
        brown = f["brown_fraction"]
        white = f["white_fraction"]
        affected = f["affected_fraction"]
        spot_count = f["spot_count"]
        largest_lesion = f["largest_lesion_fraction"]

        # Mostly-green, little damage AND no scattered lesions -> healthy. The
        # spot-count guard matters: a leaf peppered with small discrete spots is
        # the classic leaf-spot look even when the total dead area is modest.
        if affected < 0.12 and white < 0.05 and spot_count < 5:
            conf = 0.75 + min(0.2, green * 0.2)
            return "healthy", round(min(conf, 0.95), 2)

        # Powdery-mildew coating: notable low-saturation bright patches.
        if white >= 0.06 and white >= brown:
            conf = 0.55 + min(0.3, white)
            return "powdery_mildew", round(min(conf, 0.9), 2)

        # One or few large dead blotches -> blight (aggressive necrosis).
        if largest_lesion >= 0.20 and brown >= 0.08 and brown >= yellow:
            conf = 0.5 + min(0.35, largest_lesion)
            return "blight", round(min(conf, 0.9), 2)

        # Many discrete lesions scattered across the leaf -> leaf spot. Driven by
        # the spot count so it fires even when each spot is small.
        if spot_count >= 5 and brown >= yellow:
            conf = 0.5 + min(0.35, spot_count / 40.0 + brown)
            return "fungal_leaf_spot", round(min(conf, 0.9), 2)

        # Broader browning without a clear large-blotch pattern -> leaf spot.
        if brown >= 0.10 and brown >= yellow:
            conf = 0.45 + min(0.3, brown)
            return "fungal_leaf_spot", round(min(conf, 0.85), 2)

        # Yellowing dominates without heavy necrosis -> nutrient/chlorosis.
        if yellow >= 0.12 and yellow >= brown:
            conf = 0.5 + min(0.3, yellow)
            return "nutrient_deficiency", round(min(conf, 0.85), 2)

        # Damage present but pattern unclear.
        return "general_stress", round(0.35 + min(0.2, affected * 0.3), 2)

    # ── severity + payload assembly ────────────────────────────────────────────

    @staticmethod
    def _severity(condition_id: str, affected_fraction: float) -> Dict[str, Any]:
        if condition_id == "healthy":
            return {"level": "none", "affected_percent": 0}
        pct = int(round(affected_fraction * 100))
        if affected_fraction >= 0.5:
            level = "high"
        elif affected_fraction >= 0.2:
            level = "moderate"
        else:
            level = "low"
        return {"level": level, "affected_percent": pct}

    @staticmethod
    def _build_payload(
        condition_id: str,
        confidence: float,
        features: Dict[str, Any],
        source: str,
        message: Optional[str] = None,
    ) -> Dict[str, Any]:
        entry = get_condition(condition_id)
        severity = DiseaseDetector._severity(entry["id"], features.get("affected_fraction", 0.0))
        is_healthy = entry["id"] == "healthy"

        return {
            "status": "ok",
            "message": message or "",
            "is_healthy": is_healthy,
            "confidence": round(float(confidence), 2),
            "source": source,  # "model" | "heuristic"
            "disease": {
                "id": entry["id"],
                "name": entry["name"],
                "also_known_as": entry.get("also_known_as", ""),
                "description": entry.get("description", ""),
            },
            "severity": severity,
            "symptoms": entry.get("symptoms", []),
            "causes": entry.get("causes", []),
            "solutions": entry.get("solutions", []),
            "prevention": entry.get("prevention", []),
            "observations": features,
            "disclaimer": (
                "This is an automated visual screening from a single photo, not "
                "a lab diagnosis. Confirm with a local agricultural expert "
                "before applying chemical treatments."
            ),
        }
