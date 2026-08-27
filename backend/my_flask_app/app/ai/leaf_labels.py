"""Reading the leaf-disease model's labels.

The trained model (see ``tools/train_leaf_disease.py``) predicts fine-grained
``<crop>___<condition>`` classes — ``tomato___late_blight``, ``apple___scab`` —
because that is the granularity the public datasets label at, and it is far
more useful to a farmer than a category.

The knowledge base in :mod:`app.ai.knowledge_base`, however, is deliberately
coarse: seven conditions with treatment advice that holds across crops. Both
are worth keeping, and this module is the join between them:

    tomato___late_blight
        -> shown as   "Tomato Late Blight"          (what it is)
        -> advised as knowledge-base id "blight"    (what to do about it)

Keeping the two separate matters. Collapsing the model's answer into the
category would throw away the crop and the specific pathogen — the app would
say "Blight" when the model actually knows it is late blight on tomato, which
is the difference between generic advice and a decision about whether to pull
the crop. Going the other way and inventing per-crop treatment text we do not
have would be worse.

A label this module cannot parse is reported as unmapped rather than forced
into the nearest category, exactly as :mod:`app.ai.crop_model` does for the
field-scan models.
"""

from __future__ import annotations

import re
from typing import Any, Dict, Optional

# Crop token -> display name.
CROP_NAMES = {
    "apple": "Apple",
    "blueberry": "Blueberry",
    "cherry": "Cherry",
    "corn": "Corn (maize)",
    "grape": "Grape",
    "orange": "Orange",
    "peach": "Peach",
    "pepper": "Bell pepper",
    "potato": "Potato",
    "raspberry": "Raspberry",
    "soybean": "Soybean",
    "squash": "Squash",
    "strawberry": "Strawberry",
    "tomato": "Tomato",
}

# Condition token -> (display name, knowledge-base id).
#
# The knowledge-base id decides which treatment text the farmer is shown, so
# these are grouped by *what you do about it*, not by taxonomy:
#   - anything that presents as discrete fungal/bacterial lesions -> leaf spot
#   - fast-spreading necrosis that can take the crop -> blight
#   - a surface coating -> powdery mildew
#   - insect-vectored or insect-caused -> pest damage (the action is the vector)
#   - mechanically spread viruses have no chemical control -> general stress
CONDITIONS = {
    "healthy":                 ("Healthy", "healthy"),
    "scab":                    ("Scab", "fungal_leaf_spot"),
    "black_rot":               ("Black Rot", "fungal_leaf_spot"),
    "cedar_rust":              ("Cedar Rust", "fungal_leaf_spot"),
    "common_rust":             ("Rust", "fungal_leaf_spot"),
    "gray_leaf_spot":          ("Gray Leaf Spot", "fungal_leaf_spot"),
    "septoria_leaf_spot":      ("Septoria Leaf Spot", "fungal_leaf_spot"),
    "bacterial_spot":          ("Bacterial Spot", "fungal_leaf_spot"),
    "leaf_spot":               ("Leaf Spot", "fungal_leaf_spot"),
    "target_spot":             ("Target Spot", "fungal_leaf_spot"),
    "leaf_scorch":             ("Leaf Scorch", "fungal_leaf_spot"),
    "esca":                    ("Esca (Black Measles)", "fungal_leaf_spot"),
    "early_blight":            ("Early Blight", "blight"),
    "late_blight":             ("Late Blight", "blight"),
    "northern_leaf_blight":    ("Northern Leaf Blight", "blight"),
    "leaf_blight":             ("Leaf Blight", "blight"),
    "powdery_mildew":          ("Powdery Mildew", "powdery_mildew"),
    "leaf_mold":               ("Leaf Mould", "powdery_mildew"),
    "spider_mites":            ("Spider Mites", "pest_damage"),
    "yellow_leaf_curl_virus":  ("Yellow Leaf Curl Virus", "pest_damage"),
    "citrus_greening":         ("Citrus Greening (HLB)", "pest_damage"),
    "mosaic_virus":            ("Mosaic Virus", "general_stress"),

    # Coarse fallbacks. These are not classes the bundled model predicts, but a
    # model trained elsewhere may use category-level labels ("blight", "rust"),
    # and the token scan below tries longer names first — so `late_blight` still
    # wins over `blight` for a label that carries both.
    "blight":                  ("Blight", "blight"),
    "rust":                    ("Rust", "fungal_leaf_spot"),
    "mildew":                  ("Mildew", "powdery_mildew"),
    "mosaic":                  ("Mosaic Virus", "general_stress"),
    "chlorosis":               ("Chlorosis", "nutrient_deficiency"),
    "nutrient":                ("Nutrient Deficiency", "nutrient_deficiency"),
    "pest":                    ("Pest Damage", "pest_damage"),
}

# The model's "there is no leaf in this photo" class. PlantVillage ships it and
# it earns its place: without it the model answers a photo of the ground with a
# confident disease name.
NOT_A_LEAF = "not_a_leaf"


def _normalise(label: str) -> str:
    text = str(label or "").strip().lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return re.sub(r"_+", "_", text).strip("_")


def parse(label: str) -> Optional[Dict[str, Any]]:
    """Split a model label into crop, condition, display name and KB id.

    Returns ``None`` for a label this module does not recognise — the caller
    should then fall back rather than present a guess as a diagnosis.
    """
    key = _normalise(label)
    if not key:
        return None

    if key == NOT_A_LEAF or "background" in key:
        return {
            "label": str(label),
            "crop": None,
            "crop_name": None,
            "condition": NOT_A_LEAF,
            "display_name": "No leaf detected",
            "knowledge_base_id": "general_stress",
            "is_healthy": False,
            "is_leaf": False,
        }

    crop_token: Optional[str] = None
    condition_token: Optional[str] = None

    if "___" in key:
        crop_part, _, condition_part = key.partition("___")
        crop_token = crop_part if crop_part in CROP_NAMES else None
        condition_token = condition_part if condition_part in CONDITIONS else None

    # Fall back to a token scan, so a model trained on somebody else's folder
    # names ("Tomato_Late_blight") still resolves.
    if condition_token is None:
        for token, _value in sorted(CONDITIONS.items(), key=lambda kv: -len(kv[0])):
            if token in key:
                condition_token = token
                break
    if crop_token is None:
        for token in CROP_NAMES:
            if token in key:
                crop_token = token
                break

    if condition_token is None:
        return None

    condition_name, kb_id = CONDITIONS[condition_token]
    crop_name = CROP_NAMES.get(crop_token or "")

    if condition_token == "healthy":
        display = f"Healthy {crop_name}" if crop_name else "Healthy plant"
    elif crop_name:
        display = f"{crop_name} {condition_name}"
    else:
        display = condition_name

    return {
        "label": str(label),
        "crop": crop_token,
        "crop_name": crop_name,
        "condition": condition_token,
        "display_name": display,
        "knowledge_base_id": kb_id,
        "is_healthy": condition_token == "healthy",
        "is_leaf": True,
    }


def describe(label: str) -> Dict[str, Any]:
    """``parse`` with an honest placeholder instead of ``None``.

    Used where the response must carry *something* for an unrecognised label:
    the raw label is surfaced as-is and routed to the inconclusive entry, so an
    operator sees "the model said X and we don't know what X is" rather than a
    confident wrong diagnosis.
    """
    parsed = parse(label)
    if parsed is not None:
        return parsed
    return {
        "label": str(label),
        "crop": None,
        "crop_name": None,
        "condition": None,
        "display_name": str(label),
        "knowledge_base_id": "general_stress",
        "is_healthy": False,
        "is_leaf": True,
        "unmapped": True,
    }
