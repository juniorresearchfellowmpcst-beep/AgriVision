"""Optional trained-model hook for disease identification.

The feature works out of the box using the colour/lesion heuristic in
:mod:`app.ai.disease_detector`. This module is the clean seam for dropping in a
*real* trained classifier later (the project already ships torch/torchvision in
requirements.txt) without touching the route or service layers.

To enable a model, set two environment variables and restart the backend::

    AI_DISEASE_MODEL_PATH=/abs/path/to/model.pt     # TorchScript module
    AI_DISEASE_LABELS_PATH=/abs/path/to/labels.txt  # one class name per line

The label names in ``labels.txt`` should map onto the knowledge-base ids in
:mod:`app.ai.knowledge_base` (e.g. ``fungal_leaf_spot``); anything unrecognised
falls back gracefully to a general-stress entry. If the model can't be loaded
for any reason we log and fall back to the heuristic — the endpoint never fails
just because a model is misconfigured.
"""

from __future__ import annotations

import logging
import os
import threading
from typing import List, Optional, Tuple

import numpy as np

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_loaded = False
_model = None  # torch.jit.ScriptModule when available
_labels: List[str] = []


def _load() -> None:
    """Attempt a one-time lazy load of the optional TorchScript model."""
    global _loaded, _model, _labels
    if _loaded:
        return

    with _lock:
        if _loaded:
            return
        _loaded = True  # mark attempted regardless of outcome

        model_path = os.environ.get("AI_DISEASE_MODEL_PATH")
        labels_path = os.environ.get("AI_DISEASE_LABELS_PATH")
        if not model_path or not os.path.isfile(model_path):
            return  # no model configured -> heuristic path

        try:
            import torch  # imported lazily so the app starts without torch loaded

            model = torch.jit.load(model_path, map_location="cpu")
            model.eval()

            labels: List[str] = []
            if labels_path and os.path.isfile(labels_path):
                with open(labels_path, "r", encoding="utf-8") as fh:
                    labels = [ln.strip() for ln in fh if ln.strip()]

            _model = model
            _labels = labels
            logger.info("Loaded disease model from %s (%d labels)", model_path, len(labels))
        except Exception as exc:  # pragma: no cover - depends on external file
            logger.warning("Disease model unavailable, using heuristic: %s", exc)
            _model = None
            _labels = []


def is_available() -> bool:
    _load()
    return _model is not None


def predict(img_bgr: np.ndarray) -> Optional[Tuple[str, float]]:
    """Return ``(label, confidence)`` from the trained model, or ``None``.

    ``None`` means "no model / prediction unavailable" — callers should fall
    back to the heuristic classifier.
    """
    _load()
    if _model is None:
        return None

    try:
        import cv2
        import torch

        # Standard ImageNet-style preprocessing: 224x224 RGB, normalised.
        rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        rgb = cv2.resize(rgb, (224, 224), interpolation=cv2.INTER_AREA)
        arr = rgb.astype(np.float32) / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        arr = (arr - mean) / std
        tensor = torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0)

        with torch.no_grad():
            out = _model(tensor)
            probs = torch.softmax(out, dim=1)[0]
            conf, idx = torch.max(probs, dim=0)

        index = int(idx.item())
        label = _labels[index] if 0 <= index < len(_labels) else str(index)
        return label, float(conf.item())
    except Exception as exc:  # pragma: no cover - depends on external model
        logger.warning("Disease model inference failed, using heuristic: %s", exc)
        return None
