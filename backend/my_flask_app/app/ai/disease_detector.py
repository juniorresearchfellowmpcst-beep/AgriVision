"""Plant-leaf disease identification from a single RGB photo.

Pipeline
--------
1. Decode the uploaded photo (:func:`app.ai.utils.decode_image`).
2. Measure colour/lesion features (:func:`app.ai.utils.extract_features`) — used
   for the severity estimate on every path, and for the diagnosis itself when
   no model is configured.
3. If a trained model is configured (:mod:`app.ai.model_loader`), take its
   fine-grained ``<crop>___<condition>`` answer; otherwise classify from the
   features with the rules in :meth:`DiseaseDetector._classify`.
4. Resolve treatment guidance from the knowledge base
   (:mod:`app.ai.knowledge_base`) and attach a severity estimate.

Two answers, one response
-------------------------
The model knows *what* ("Tomato Late Blight"); the knowledge base knows *what
to do* (the seven condition entries, whose advice holds across crops). The
response carries both: ``disease.name`` is the specific finding and
``disease.category`` is the entry the symptoms/causes/solutions came from. The
severity always comes from the image measurement rather than the classifier,
because a class tells you which disease and the pixels tell you how much of the
leaf it has taken.

The public entry point is :func:`DiseaseDetector.detect`, which returns a plain
dict ready to be JSON-serialised by the service/route layers.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

from app.ai import leaf_labels, model_loader, utils
from app.ai.knowledge_base import get_condition

# How many candidate classes to carry back. The runner-up is worth showing: the
# two blights and the several leaf spots are genuinely hard to separate from a
# single photo, and a close second is information the farmer should have.
_TOP_K = 3

# Below this, say so rather than presenting the answer as settled.
_LOW_CONFIDENCE = 0.55


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
        predictions = model_loader.predict_topk(img, k=_TOP_K)

        if predictions:
            return DiseaseDetector._from_model(predictions, features)
        return DiseaseDetector._from_heuristic(features)

    # ── model path ────────────────────────────────────────────────────────────

    @staticmethod
    def _from_model(
        predictions: List[Tuple[str, float]], features: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Build the response from the trained classifier's ranked answer."""
        top_label, top_confidence = predictions[0]
        parsed = leaf_labels.describe(top_label)

        # The model has a "no leaf in this photo" class, and it is a better
        # judge of that than the heuristic's green-pixel test — a real field
        # photo with soil and sky in frame often fails the latter while the
        # model reads it fine. So on the model path the model decides.
        if not parsed.get("is_leaf", True):
            payload = DiseaseDetector._build_payload(
                condition_id="general_stress",
                confidence=top_confidence,
                features=features,
                source="model",
                predictions=predictions,
            )
            payload["message"] = (
                "No leaf found in this photo. Fill more of the frame with a "
                "single, well-lit leaf for a diagnosis."
            )
            payload["low_confidence"] = True
            return payload

        payload = DiseaseDetector._build_payload(
            condition_id=parsed["knowledge_base_id"],
            confidence=top_confidence,
            features=features,
            source="model",
            parsed=parsed,
            predictions=predictions,
        )

        if top_confidence < _LOW_CONFIDENCE:
            payload["low_confidence"] = True
            runner_up = predictions[1] if len(predictions) > 1 else None
            if runner_up is not None:
                other = leaf_labels.describe(runner_up[0])
                payload["message"] = (
                    f"Not a confident call — this looks most like "
                    f"{parsed['display_name']}, but {other['display_name']} is "
                    f"close behind. A second photo in better light will help."
                )
            else:
                payload["message"] = (
                    "Not a confident call. Try a second photo of the same leaf "
                    "in better light, filling more of the frame."
                )
        return payload

    # ── heuristic path ────────────────────────────────────────────────────────

    @staticmethod
    def _from_heuristic(features: Dict[str, Any]) -> Dict[str, Any]:
        """Build the response from the colour/lesion rules (no model configured)."""
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

        condition_id, confidence = DiseaseDetector._classify(features)
        return DiseaseDetector._build_payload(
            condition_id=condition_id,
            confidence=confidence,
            features=features,
            source="heuristic",
        )

    @staticmethod
    def _classify(f: Dict[str, Any]) -> Tuple[str, float]:
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
        parsed: Optional[Dict[str, Any]] = None,
        predictions: Optional[List[Tuple[str, float]]] = None,
    ) -> Dict[str, Any]:
        entry = get_condition(condition_id)
        is_healthy = (
            parsed["is_healthy"] if parsed is not None else entry["id"] == "healthy"
        )
        severity = DiseaseDetector._severity(
            "healthy" if is_healthy else entry["id"],
            features.get("affected_fraction", 0.0),
        )

        # The headline name is the model's specific finding when there is one,
        # and the knowledge-base entry's name otherwise. `category` always says
        # which entry the advice below it came from, so a farmer reading
        # "Tomato Late Blight" can see the guidance is the general blight
        # guidance rather than something tomato-specific we don't have.
        disease: Dict[str, Any] = {
            "id": entry["id"],
            "name": entry["name"],
            "also_known_as": entry.get("also_known_as", ""),
            "description": entry.get("description", ""),
            "crop": None,
            "label": None,
            "category": {"id": entry["id"], "name": entry["name"]},
        }
        if parsed is not None:
            disease["name"] = parsed["display_name"]
            disease["crop"] = parsed.get("crop_name")
            disease["label"] = parsed.get("label")
            if parsed.get("unmapped"):
                disease["unmapped"] = True

        payload = {
            "status": "ok",
            "message": message or "",
            "is_healthy": is_healthy,
            "confidence": round(float(confidence), 2),
            "source": source,  # "model" | "heuristic"
            "disease": disease,
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

        if predictions:
            payload["predictions"] = [
                {
                    "label": label,
                    "name": leaf_labels.describe(label)["display_name"],
                    "confidence": round(float(score), 3),
                }
                for label, score in predictions
            ]
        return payload
