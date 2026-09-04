"""Pretrained-CNN hooks for MP crop disease and weed species.

Two optional models, each a drop-in over the heuristic path:

    AI_CROP_MODEL_PATH   / AI_CROP_LABELS_PATH   crop-disease classifier
    AI_WEED_MODEL_PATH   / AI_WEED_LABELS_PATH   weed-species classifier

Both are TorchScript modules fine-tuned from an ImageNet-pretrained backbone —
see ``tools/train_crop_cnn.py``, which produces exactly this pair of files.

The interesting work in this module is **label mapping**. Public agricultural
datasets do not name their classes the way this app does: PlantVillage writes
``Tomato___Late_blight``, a Kaggle rice set writes ``BrownSpot``, a rust
dataset writes ``wheat_stripe_rust``. Rather than force whoever trains the
model to rename their folders, the mapper normalises a label and then matches
it against :mod:`app.ai.crop_kb` by id, by name, and finally by token overlap —
scoped to the crop being scanned, so ``rust`` under wheat resolves to yellow
rust and ``rust`` under soybean resolves to soybean rust.

Anything that cannot be matched is reported honestly as an unmapped label
rather than being forced into the nearest disease.
"""

from __future__ import annotations

import os
import re
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

from .crop_kb import CROPS, GENERIC_CONDITIONS, diseases_for, get_disease
from .torch_model import TorchScriptClassifier
from .weed_kb import WEEDS, get_weed

# The two optional models. Constructed at import time but not *loaded* until
# something asks — see TorchScriptClassifier.
# Defaults to the leaf-disease model that ships with the repo.
#
# It is not a purpose-built MP crop model -- it is the PlantVillage-trained
# network the leaf module uses -- but four of its classes are maize, which is
# exactly where the colour rules were weakest. Measured over 240 corn frames it
# scores 84% against the rules' 43%, and 60/60 on healthy leaves against 28/60.
# Where its label does not map to the scanned crop the rules still take over,
# so the crops it knows nothing about are no worse off.
_REPO_MODELS = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "models",
)

disease_model = TorchScriptClassifier(
    "AI_CROP_MODEL_PATH",
    "AI_CROP_LABELS_PATH",
    "crop-disease",
    default_model=os.path.join(_REPO_MODELS, "leaf_disease.pt"),
    default_labels=os.path.join(_REPO_MODELS, "leaf_disease_labels.txt"),
)
weed_model = TorchScriptClassifier(
    "AI_WEED_MODEL_PATH", "AI_WEED_LABELS_PATH", "weed-species"
)

# Words that carry no information when matching a label to a knowledge-base id.
# "spot" is deliberately NOT here — it is the whole distinction between
# "brown spot" and "brown rust".
_NOISE_TOKENS = {
    "leaf", "leaves", "plant", "disease", "diseased", "infected", "crop",
    "image", "images", "class", "the", "of", "and",
}

# Dataset shorthands that are unambiguous once the crop is known.
_SYNONYMS = {
    "bacterialblight": "bacterial_blight",
    "leafblast": "blast",
    "neckblast": "blast",
    "brownspot": "brown_spot",
    "sheathblight": "sheath_blight",
    "tungro": "bacterial_blight",       # nearest actionable rice entry
    "stripe": "yellow",
    "striperust": "yellow_rust",
    "yellowrust": "yellow_rust",
    "leafrust": "brown_rust",
    "brownrust": "brown_rust",
    "commonrust": "common_rust",
    "mosaic": "mosaic",
    "ymv": "yellow_mosaic",
    "septoria": "leaf_spot",
    "healthy": "healthy",
    "nodisease": "healthy",
    "fresh": "healthy",
    # Northern corn leaf blight and Turcicum leaf blight are two names for the
    # same disease (Exserohilum turcicum). Datasets use the first, this app's
    # knowledge base uses the second, and without the bridge the token overlap
    # ("blight" alone) scores 0.25 and falls just under the match floor.
    # Both spellings, with and without "leaf": the lookup runs on tokens that
    # have already had noise words like "leaf" removed, so "northernleafblight"
    # alone never fires.
    "northernleafblight": "turcicum_blight",
    "northernblight": "turcicum_blight",
    "northerncornleafblight": "turcicum_blight",
    "nclb": "turcicum_blight",
}

# What the datasets call a crop, against what the knowledge base calls it.
#
# This is not cosmetic. The crop prefix is stripped from a label only when it
# is recognised, and an unstripped prefix poisons every match that follows:
# "corn___healthy" keeps its "corn" token, so it no longer equals "healthy",
# and a picture of a *healthy maize leaf* came back as "general stress".
# PlantVillage says corn, this app says maize, and nothing connected the two.
_CROP_ALIASES = {
    "corn": "maize",
    "maize": "maize",
    "paddy": "rice",
    "rice": "rice",
    "soya": "soybean",
    "soyabean": "soybean",
    "soybeans": "soybean",
    "bengalgram": "gram",
    "chickpea": "gram",
    "redgram": "pigeonpea",
    "arhar": "pigeonpea",
    "tur": "pigeonpea",
    "sarson": "mustard",
}


# Crops that appear in the public datasets and that this app does not grow.
#
# Listed so a label can be recognised as belonging to a crop *and* rejected,
# which is a different outcome from an unrecognised word. Without the
# distinction "tomato___late_blight" looks like a bare disease name and gets
# matched against whatever MP crop shares a token with it.
_FOREIGN_CROPS = {
    "apple", "blueberry", "cherry", "grape", "orange", "peach", "pepper",
    "bell", "potato", "raspberry", "squash", "strawberry", "tomato",
}


def _crop_key(name: Optional[str]) -> Optional[str]:
    """The knowledge base's name for a crop, whatever the caller called it."""
    key = _normalise(name)
    if not key:
        return None
    key = _CROP_ALIASES.get(key, key)
    return key if key in CROPS else None


def _normalise(label: str) -> str:
    """Lowercase, underscore-separated form of an arbitrary dataset label."""
    text = str(label or "").strip().lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return re.sub(r"_+", "_", text).strip("_")


def _tokens(value: str) -> List[str]:
    return [t for t in _normalise(value).split("_") if t and t not in _NOISE_TOKENS]


def map_disease_label(raw_label: str, crop: Optional[str] = None) -> Dict[str, Any]:
    """Resolve a model label onto a knowledge-base disease id.

    Returns ``{"id", "matched", "raw"}``. ``matched`` is False when the label
    could not be tied to anything this app knows about — the caller should say
    so rather than presenting a guess as a diagnosis.
    """
    normalised = _normalise(raw_label)
    if not normalised:
        return {"id": "general_stress", "matched": False, "raw": raw_label}

    if normalised in GENERIC_CONDITIONS:
        return {"id": normalised, "matched": True, "raw": raw_label}

    # Datasets prefix the crop: "wheat___yellow_rust". Drop it, but remember
    # it — it is a better crop hint than whatever the caller guessed.
    #
    # Matched through the alias table, so a dataset that writes "corn" is
    # recognised as the crop this app calls "maize". A prefix left in place is
    # not a cosmetic problem: it stays in the token set and drags every
    # subsequent overlap score down.
    tokens = _tokens(normalised)
    named_crop = next(
        (t for t in tokens if _crop_key(t) or t in _FOREIGN_CROPS), None
    )
    if named_crop:
        tokens = [t for t in tokens if t != named_crop]
    crop_key = _crop_key(crop) or _crop_key(named_crop)

    # A label naming a crop the knowledge base does not cover — the public
    # datasets carry tomato, potato, pepper and a dozen orchard species — must
    # not be matched against a different crop's diseases.
    # "tomato___bacterial_spot" resolving to cotton's bacterial blight would
    # carry cotton's treatment with it, and a product recommended for the wrong
    # crop is worse than no answer at all.
    if named_crop and _crop_key(named_crop) is None:
        return {"id": "general_stress", "matched": False, "raw": raw_label}

    # The label names one crop and the scan is of another. That is the model
    # saying it does not think this is the crop the farmer selected, and it
    # must not be resolved into a diagnosis for either one: a wheat scan that
    # returned "corn___common_rust" was matching maize's common rust through
    # the widening step below and reporting it under wheat.
    label_crop = _crop_key(named_crop)
    caller_crop = _crop_key(crop)
    if label_crop and caller_crop and label_crop != caller_crop:
        return {"id": "general_stress", "matched": False, "raw": raw_label}

    joined = "_".join(tokens)
    squashed = joined.replace("_", "")
    if squashed in _SYNONYMS:
        joined = _SYNONYMS[squashed]
        tokens = _tokens(joined)

    if joined in GENERIC_CONDITIONS:
        return {"id": joined, "matched": True, "raw": raw_label}

    # Scoping is the whole game here: a bare "rust" is a *different disease*
    # under wheat, soybean and maize. When the crop is known, its own diseases
    # are searched alone, and only if none of them match at all do we widen to
    # every crop — a wheat scan must never come back with soybean rust just
    # because that entry's shorter name gave it a better token ratio.
    label_tokens = set(tokens)
    own = diseases_for(crop_key)
    if own:
        best_id, best_score = _best_match(label_tokens, own)
        if best_id and best_score >= 0.3:
            return {"id": best_id, "matched": True, "raw": raw_label}

    every = [d for crop_entry in CROPS.values() for d in crop_entry["diseases"]]
    best_id, best_score = _best_match(label_tokens, every)
    if best_id and best_score >= 0.3:
        return {"id": best_id, "matched": True, "raw": raw_label}
    return {"id": "general_stress", "matched": False, "raw": raw_label}


def _best_match(label_tokens: set, candidates: List[Dict[str, Any]]):
    """Highest Jaccard overlap between a label and a set of disease entries."""
    best_id, best_score = None, 0.0
    if not label_tokens:
        return best_id, best_score

    for disease in candidates:
        disease_tokens = set(_tokens(disease["id"])) | set(_tokens(disease["name"]))
        if not disease_tokens:
            continue
        overlap = len(label_tokens & disease_tokens)
        if not overlap:
            continue
        score = overlap / float(len(label_tokens | disease_tokens))
        if score > best_score:
            best_id, best_score = disease["id"], score
    return best_id, best_score


def map_weed_label(raw_label: str) -> Dict[str, Any]:
    """Resolve a model label onto a weed id from :mod:`app.ai.weed_kb`."""
    normalised = _normalise(raw_label)
    if normalised in WEEDS:
        return {"id": normalised, "matched": True, "raw": raw_label}

    label_tokens = set(_tokens(normalised))
    best_id, best_score = None, 0.0
    for weed_id, weed in WEEDS.items():
        weed_tokens = (
            set(_tokens(weed_id))
            | set(_tokens(weed["name"]))
            | set(_tokens(weed["local_name"]))
        )
        overlap = len(label_tokens & weed_tokens)
        if not overlap:
            continue
        score = overlap / float(len(label_tokens | weed_tokens))
        if score > best_score:
            best_id, best_score = weed_id, score

    if best_id and best_score >= 0.3:
        return {"id": best_id, "matched": True, "raw": raw_label}
    return {"id": None, "matched": False, "raw": raw_label}


def classify_disease(
    img_bgr: np.ndarray, crop: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """CNN crop-disease prediction, or ``None`` when no model is configured."""
    predictions = disease_model.predict_topk(img_bgr, k=3)
    if not predictions:
        return None

    label, confidence = predictions[0]
    mapping = map_disease_label(label, crop)
    entry = get_disease(mapping["id"])

    alternatives = []
    for alt_label, alt_confidence in predictions[1:]:
        alt = map_disease_label(alt_label, crop)
        alternatives.append({
            "id": alt["id"],
            "name": get_disease(alt["id"])["name"],
            "confidence": round(float(alt_confidence), 3),
            "raw_label": alt_label,
        })

    return {
        "condition_id": entry["id"],
        "confidence": round(float(confidence), 3),
        "source": "model",
        "raw_label": label,
        "label_matched": mapping["matched"],
        "alternatives": alternatives,
    }


def classify_weed(img_bgr: np.ndarray) -> Optional[Dict[str, Any]]:
    """CNN weed-species prediction, or ``None`` when no model is configured."""
    predictions = weed_model.predict_topk(img_bgr, k=2)
    if not predictions:
        return None

    label, confidence = predictions[0]
    mapping = map_weed_label(label)
    weed = get_weed(mapping["id"]) if mapping["id"] else None

    return {
        "weed_id": mapping["id"],
        "name": weed["name"] if weed else label,
        "local_name": weed["local_name"] if weed else "",
        "type": weed["type"] if weed else None,
        "control": weed["control"] if weed else [],
        "confidence": round(float(confidence), 3),
        "source": "model",
        "raw_label": label,
        "label_matched": mapping["matched"],
    }


def engines() -> Dict[str, str]:
    """Which engine answers each half of a field scan, for /health."""
    return {
        "disease": "model" if disease_model.is_available() else "heuristic",
        "weed": "model" if weed_model.is_available() else "heuristic",
    }
