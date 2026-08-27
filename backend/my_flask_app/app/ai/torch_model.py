"""A reusable TorchScript classifier seam.

Every CNN in this project is optional in exactly the same way: the feature
works without it using an OpenCV heuristic, and a trained model — exported as
TorchScript and pointed at by two environment variables — takes over when one
is present. The rules that make that safe are all in one place here:

  * loading is lazy and attempted **once**, so a missing file costs one check
    rather than a stack trace per request;
  * any failure (no torch installed, corrupt file, wrong input shape) logs and
    returns ``None``, which every caller reads as "use the heuristic";
  * preprocessing is the ImageNet convention that torchvision's pretrained
    backbones expect, because that is what a fine-tuned ResNet/MobileNet/
    EfficientNet will have been trained with.

See ``docs/CROP_CNN_TRAINING.md`` and ``tools/train_crop_cnn.py`` for producing
the model files this loads.
"""

from __future__ import annotations

import logging
import os
import threading
from typing import List, Optional, Tuple

import numpy as np

logger = logging.getLogger(__name__)

# torchvision's pretrained-model normalisation. Change these and a fine-tuned
# backbone quietly loses accuracy without ever raising an error.
_IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


class TorchScriptClassifier:
    """One optional image classifier, configured by environment variables."""

    def __init__(
        self,
        model_env: str,
        labels_env: str,
        name: str,
        input_size: int = 224,
    ):
        self.model_env = model_env
        self.labels_env = labels_env
        self.name = name
        self.input_size = input_size

        self._lock = threading.Lock()
        self._loaded = False
        self._model = None
        self._labels: List[str] = []

    # ── loading ───────────────────────────────────────────────────────────

    def _resolve_input_size(self, model_path: str) -> None:
        """Adopt the size the model was actually trained at, if it says so.

        Every trainer in ``tools/`` writes a ``<stem>_report.json`` beside the
        model recording ``img_size``. Reading it back removes the one silent
        failure this seam has: a model trained at 192 and served at 224 raises
        nothing, it just quietly gets worse. If the sidecar is missing we keep
        the constructor's default, which is the ImageNet convention.
        """
        stem = os.path.splitext(model_path)[0]
        report_path = f"{stem}_report.json"
        if not os.path.isfile(report_path):
            return
        try:
            import json

            with open(report_path, "r", encoding="utf-8") as handle:
                size = int(json.load(handle).get("img_size") or 0)
            if 64 <= size <= 1024:
                if size != self.input_size:
                    logger.info(
                        "%s: using input size %d from %s (default was %d)",
                        self.name, size, os.path.basename(report_path), self.input_size,
                    )
                self.input_size = size
        except Exception as exc:  # pragma: no cover - malformed sidecar
            logger.warning("%s: could not read %s: %s", self.name, report_path, exc)

    def _load(self) -> None:
        if self._loaded:
            return
        with self._lock:
            if self._loaded:
                return
            self._loaded = True  # attempted, whatever the outcome

            model_path = os.environ.get(self.model_env)
            if not model_path or not os.path.isfile(model_path):
                return  # not configured -> heuristic path

            try:
                import torch

                model = torch.jit.load(model_path, map_location="cpu")
                model.eval()
                self._resolve_input_size(model_path)

                labels: List[str] = []
                labels_path = os.environ.get(self.labels_env)
                if labels_path and os.path.isfile(labels_path):
                    with open(labels_path, "r", encoding="utf-8") as handle:
                        labels = [line.strip() for line in handle if line.strip()]

                self._model = model
                self._labels = labels
                logger.info(
                    "Loaded %s model from %s (%d labels)",
                    self.name, model_path, len(labels),
                )
            except Exception as exc:  # pragma: no cover - depends on the file
                logger.warning(
                    "%s model unavailable, falling back to the heuristic: %s",
                    self.name, exc,
                )
                self._model = None
                self._labels = []

    def is_available(self) -> bool:
        self._load()
        return self._model is not None

    @property
    def labels(self) -> List[str]:
        self._load()
        return list(self._labels)

    # ── inference ─────────────────────────────────────────────────────────

    def _tensor(self, img_bgr: np.ndarray):
        import cv2
        import torch

        image = img_bgr
        if image.ndim == 2:
            image = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
        elif image.shape[2] == 4:
            image = cv2.cvtColor(image, cv2.COLOR_BGRA2BGR)
        if image.dtype != np.uint8:
            # A 16-bit frame would otherwise be read as a wildly out-of-range
            # float and produce confident nonsense.
            image = cv2.normalize(image, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)

        rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        rgb = cv2.resize(
            rgb, (self.input_size, self.input_size), interpolation=cv2.INTER_AREA
        )
        array = (rgb.astype(np.float32) / 255.0 - _IMAGENET_MEAN) / _IMAGENET_STD
        return torch.from_numpy(array).permute(2, 0, 1).unsqueeze(0)

    def predict(self, img_bgr: np.ndarray) -> Optional[Tuple[str, float]]:
        """``(label, confidence)`` from the model, or ``None`` to fall back."""
        top = self.predict_topk(img_bgr, k=1)
        return top[0] if top else None

    def predict_topk(
        self, img_bgr: np.ndarray, k: int = 3
    ) -> Optional[List[Tuple[str, float]]]:
        """The k most likely labels, or ``None`` when there is no model.

        The runner-up matters here: "yellow rust 0.51 / brown rust 0.47" is a
        different message to the operator than a confident single answer, and
        the two rusts need different varietal decisions next season.
        """
        self._load()
        if self._model is None:
            return None

        try:
            import torch

            with torch.no_grad():
                output = self._model(self._tensor(img_bgr))
                probabilities = torch.softmax(output, dim=1)[0]
                count = min(int(k), probabilities.shape[0])
                scores, indices = torch.topk(probabilities, count)

            results = []
            for score, index in zip(scores.tolist(), indices.tolist()):
                label = (
                    self._labels[index]
                    if 0 <= index < len(self._labels)
                    else str(index)
                )
                results.append((label, float(score)))
            return results
        except Exception as exc:  # pragma: no cover - depends on the model
            logger.warning("%s inference failed, using the heuristic: %s", self.name, exc)
            return None
