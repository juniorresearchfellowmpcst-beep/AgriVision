"""The trained-model hook for leaf-disease identification.

``/api/disease/identify`` works with no model at all, using the colour/lesion
heuristic in :mod:`app.ai.disease_detector`. This module is the seam a real
classifier drops into. To enable one, set two environment variables and restart
the backend::

    AI_DISEASE_MODEL_PATH=/abs/path/models/leaf_disease.pt      # TorchScript
    AI_DISEASE_LABELS_PATH=/abs/path/models/leaf_disease_labels.txt

Produce that pair with ``tools/train_leaf_disease.py``, which fine-tunes a
pretrained backbone on the merged PlantVillage + PlantDoc set and writes
exactly these two files (plus a report). See ``docs/LEAF_DISEASE_MODEL.md``.

The labels are fine-grained ``<crop>___<condition>`` ids;
:mod:`app.ai.leaf_labels` turns them into a display name and the knowledge-base
id that carries the treatment advice.

Loading is lazy and attempted once, and **any** failure — torch missing, file
corrupt, wrong input shape — logs and falls back to the heuristic. The endpoint
never fails because a model was misconfigured.
"""

from __future__ import annotations

import logging
import os
from typing import List, Optional, Tuple

import numpy as np

from app.ai.torch_model import TorchScriptClassifier

logger = logging.getLogger(__name__)

# The mechanics (lazy one-shot load, ImageNet preprocessing, graceful
# fallback) are shared with the field-scan models in app/ai/crop_model.py.
# Keeping one implementation means a fix to the loading rules applies to every
# model this project serves, rather than to whichever copy someone remembered.
_classifier = TorchScriptClassifier(
    "AI_DISEASE_MODEL_PATH", "AI_DISEASE_LABELS_PATH", "leaf-disease"
)


def is_available() -> bool:
    return _classifier.is_available()


def labels() -> List[str]:
    return _classifier.labels


def predict(img_bgr: np.ndarray) -> Optional[Tuple[str, float]]:
    """``(label, confidence)`` from the trained model, or ``None``.

    ``None`` means "no model / prediction unavailable" — callers fall back to
    the heuristic classifier.
    """
    return _classifier.predict(img_bgr)


def predict_topk(
    img_bgr: np.ndarray, k: int = 3
) -> Optional[List[Tuple[str, float]]]:
    """The k most likely labels, or ``None`` when there is no model.

    The runner-up carries real information on a leaf photo: "late blight 0.52 /
    early blight 0.44" is a different message than a confident single answer,
    and the two call for different urgency.
    """
    return _classifier.predict_topk(img_bgr, k=k)


def info() -> dict:
    """What the module is serving — surfaced by ``GET /api/disease/health``."""
    model_path = os.environ.get("AI_DISEASE_MODEL_PATH") or ""
    available = is_available()
    return {
        "engine": "model" if available else "heuristic",
        "model_file": os.path.basename(model_path) if available else None,
        "input_size": _classifier.input_size if available else None,
        "classes": len(labels()) if available else 0,
    }
