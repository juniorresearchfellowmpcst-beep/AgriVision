"""Vegetation indices from a calibrated, band-aligned reflectance stack.

This module holds a **registry** of the vegetation indices used in crop
monitoring. Each entry knows its formula, the bands it needs, whether a high
value means a healthy or a stressed canopy, and a plain-language description —
so the API can advertise them and the risk/report layer can reason about them.

All indices should be computed on **reflectance** (0..1). When a capture has not
been panel-calibrated, the pipeline first rescales each band to a pseudo-
reflectance (robust per-band 0..1) so soil-adjusted indices (SAVI, EVI, ...)
still behave — results are then *relative*, good for zoning, not absolute.

Backward compatibility: `compute_index`, `compute_indices`, and `INDEX_BANDS`
keep the original signatures used by pipeline.py and the tests.
"""

import os
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional

import cv2
import numpy as np

from .io import BandStack


# ── Small numerically-safe helpers used by the formulas ──────────────────────

def _safe_div(num: np.ndarray, den: np.ndarray) -> np.ndarray:
    """num / den, returning 0 where den == 0 (no-data / dead pixels)."""
    out = np.zeros_like(num, dtype=np.float32)
    np.divide(num, den, out=out, where=den != 0)
    return out


def _nd(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Normalised difference (a - b) / (a + b), clipped to [-1, 1]."""
    return np.clip(_safe_div(a - b, a + b), -1.0, 1.0)


# Public alias kept for callers that imported it directly.
def normalized_difference(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return _nd(a.astype(np.float32), b.astype(np.float32))


# ── The index registry ───────────────────────────────────────────────────────

@dataclass(frozen=True)
class IndexSpec:
    """Everything the app needs to compute and explain one index."""

    key: str
    name: str
    formula: str
    bands: List[str]                     # bands the formula reads
    fn: Callable[[Dict[str, np.ndarray]], np.ndarray]
    category: str                        # greenness | chlorophyll | water | stress | rgb
    description: str
    # True  -> a HIGH value means a HEALTHY canopy (low risk)
    # False -> a HIGH value means MORE stress (high risk)
    higher_is_healthier: bool = True
    # Rough display range for previews and legends.
    vmin: float = -1.0
    vmax: float = 1.0
    # Approx value below which the canopy is usually a concern (healthy stacks).
    healthy_threshold: Optional[float] = None


# `b` inside each lambda is a dict {band_name: float32 array}.
_SPECS: List[IndexSpec] = [
    # ---- Broadband greenness / biomass ----
    IndexSpec("ndvi", "NDVI", "(NIR - Red) / (NIR + Red)", ["nir", "red"],
              lambda b: _nd(b["nir"], b["red"]),
              "greenness", "Canopy greenness and biomass; the workhorse index.",
              True, -1, 1, 0.4),
    IndexSpec("gndvi", "GNDVI", "(NIR - Green) / (NIR + Green)", ["nir", "green"],
              lambda b: _nd(b["nir"], b["green"]),
              "chlorophyll", "Chlorophyll / nitrogen status; sensitive at high LAI.",
              True, -1, 1, 0.5),
    IndexSpec("ndre", "NDRE", "(NIR - RedEdge) / (NIR + RedEdge)", ["nir", "red_edge"],
              lambda b: _nd(b["nir"], b["red_edge"]),
              "chlorophyll", "Chlorophyll in dense/mature canopy where NDVI saturates.",
              True, -1, 1, 0.3),
    IndexSpec("rvi", "RVI (SR)", "NIR / Red", ["nir", "red"],
              lambda b: np.clip(_safe_div(b["nir"], b["red"]), 0, 30),
              "greenness", "Simple ratio; grows with green biomass.",
              True, 0, 30, None),
    IndexSpec("dvi", "DVI", "NIR - Red", ["nir", "red"],
              lambda b: b["nir"] - b["red"],
              "greenness", "Difference vegetation index; simple biomass proxy.",
              True, -1, 1, None),

    # ---- Soil-adjusted (reduce bare-soil background) ----
    IndexSpec("savi", "SAVI", "1.5 * (NIR - Red) / (NIR + Red + 0.5)", ["nir", "red"],
              lambda b: np.clip(1.5 * _safe_div(b["nir"] - b["red"], b["nir"] + b["red"] + 0.5), -1.2, 1.2),
              "greenness", "Soil-adjusted NDVI for sparse canopy / early season.",
              True, -1, 1, 0.3),
    IndexSpec("osavi", "OSAVI", "(NIR - Red) / (NIR + Red + 0.16)", ["nir", "red"],
              lambda b: np.clip(_safe_div(b["nir"] - b["red"], b["nir"] + b["red"] + 0.16), -1.2, 1.2),
              "greenness", "Optimised soil-adjusted index; stable across soils.",
              True, -1, 1, 0.3),
    IndexSpec("msavi", "MSAVI2", "(2N+1 - sqrt((2N+1)^2 - 8(N-R))) / 2", ["nir", "red"],
              lambda b: _msavi(b["nir"], b["red"]),
              "greenness", "Self-adjusting soil index; no external L parameter.",
              True, -1, 1, 0.3),

    # ---- Atmospherically / background resistant ----
    IndexSpec("evi", "EVI", "2.5(N-R) / (N + 6R - 7.5B + 1)", ["nir", "red", "blue"],
              lambda b: np.clip(2.5 * _safe_div(b["nir"] - b["red"], b["nir"] + 6 * b["red"] - 7.5 * b["blue"] + 1), -1, 1.5),
              "greenness", "Enhanced vegetation index; robust in high biomass.",
              True, -1, 1, 0.2),
    IndexSpec("evi2", "EVI2", "2.5(N-R) / (N + 2.4R + 1)", ["nir", "red"],
              lambda b: np.clip(2.5 * _safe_div(b["nir"] - b["red"], b["nir"] + 2.4 * b["red"] + 1), -1, 1.5),
              "greenness", "Two-band EVI; use when no blue band is available.",
              True, -1, 1, 0.2),
    IndexSpec("arvi", "ARVI", "(N - (2R - B)) / (N + (2R - B))", ["nir", "red", "blue"],
              lambda b: _nd(b["nir"], 2 * b["red"] - b["blue"]),
              "greenness", "Atmospherically resistant; corrects Red with Blue.",
              True, -1, 1, 0.3),

    # ---- Chlorophyll indices (red-edge / green) ----
    IndexSpec("gci", "GCI (CIgreen)", "NIR / Green - 1", ["nir", "green"],
              lambda b: np.clip(_safe_div(b["nir"], b["green"]) - 1, -1, 15),
              "chlorophyll", "Green chlorophyll index; leaf chlorophyll content.",
              True, 0, 15, None),
    IndexSpec("reci", "RECI (CIrededge)", "NIR / RedEdge - 1", ["nir", "red_edge"],
              lambda b: np.clip(_safe_div(b["nir"], b["red_edge"]) - 1, -1, 15),
              "chlorophyll", "Red-edge chlorophyll index; strong N indicator.",
              True, 0, 15, None),
    IndexSpec("mcari", "MCARI", "((RE-R) - 0.2(RE-G)) * (RE/R)", ["red_edge", "red", "green"],
              lambda b: _mcari(b["red_edge"], b["red"], b["green"]),
              "chlorophyll", "Leaf chlorophyll absorption; low at chlorosis.",
              True, 0, 2, None),

    # ---- Stress / senescence ----
    IndexSpec("psri", "PSRI", "(Red - Green) / RedEdge", ["red", "green", "red_edge"],
              lambda b: np.clip(_safe_div(b["red"] - b["green"], b["red_edge"]), -1, 1),
              "stress", "Plant senescence reflectance; HIGH = senescing/stressed.",
              False, -1, 1, None),
    IndexSpec("sipi", "SIPI", "(NIR - Blue) / (NIR - Red)", ["nir", "blue", "red"],
              lambda b: np.clip(_safe_div(b["nir"] - b["blue"], b["nir"] - b["red"]), 0, 2),
              "stress", "Structure-insensitive pigment index; canopy stress.",
              False, 0, 2, None),

    # ---- Water ----
    IndexSpec("ndwi", "NDWI (green)", "(Green - NIR) / (Green + NIR)", ["green", "nir"],
              lambda b: _nd(b["green"], b["nir"]),
              "water", "McFeeters water index; HIGH = open water / waterlogging.",
              False, -1, 1, None),

    # ---- RGB-only (work even without NIR) ----
    IndexSpec("grvi", "GRVI/NGRDI", "(Green - Red) / (Green + Red)", ["green", "red"],
              lambda b: _nd(b["green"], b["red"]),
              "rgb", "Green-red index from RGB; greenness proxy without NIR.",
              True, -1, 1, 0.0),
    IndexSpec("vari", "VARI", "(Green - Red) / (Green + Red - Blue)", ["green", "red", "blue"],
              lambda b: np.clip(_safe_div(b["green"] - b["red"], b["green"] + b["red"] - b["blue"]), -1, 1),
              "rgb", "Visible atmospherically resistant; RGB canopy cover.",
              True, -1, 1, 0.0),
    IndexSpec("exg", "ExG", "2*Green - Red - Blue", ["green", "red", "blue"],
              lambda b: np.clip(2 * b["green"] - b["red"] - b["blue"], -1, 2),
              "rgb", "Excess green; separates canopy from soil in RGB.",
              True, -1, 2, None),
    IndexSpec("tgi", "TGI", "Green - 0.39*Red - 0.61*Blue", ["green", "red", "blue"],
              lambda b: np.clip(b["green"] - 0.39 * b["red"] - 0.61 * b["blue"], -1, 1),
              "rgb", "Triangular greenness; chlorophyll proxy from RGB.",
              True, -1, 1, None),
]


def _msavi(nir: np.ndarray, red: np.ndarray) -> np.ndarray:
    t = 2 * nir + 1
    val = (t - np.sqrt(np.maximum(t * t - 8 * (nir - red), 0.0))) / 2.0
    return np.clip(val, -1.2, 1.2)


def _mcari(re: np.ndarray, red: np.ndarray, green: np.ndarray) -> np.ndarray:
    val = ((re - red) - 0.2 * (re - green)) * _safe_div(re, red)
    return np.clip(np.nan_to_num(val, nan=0.0, posinf=0.0, neginf=0.0), 0, 2)


# key -> spec, plus the legacy {index: (nir_band, other_band)} map.
INDEX_REGISTRY: Dict[str, IndexSpec] = {s.key: s for s in _SPECS}
INDEX_BANDS = {
    "ndvi": ("nir", "red"),
    "gndvi": ("nir", "green"),
    "ndre": ("nir", "red_edge"),
}


def list_indices() -> List[Dict]:
    """Registry as JSON-serialisable metadata (for the /health capabilities)."""
    return [
        {
            "key": s.key, "name": s.name, "formula": s.formula, "bands": s.bands,
            "category": s.category, "description": s.description,
            "higher_is_healthier": s.higher_is_healthier,
        }
        for s in _SPECS
    ]


def available_indices(band_names: List[str]) -> List[str]:
    """Which registry indices can be computed from the bands we actually have."""
    have = set(band_names)
    return [s.key for s in _SPECS if have.issuperset(s.bands)]


# ── Computation ──────────────────────────────────────────────────────────────

def compute_index(stack: BandStack, name: str) -> np.ndarray:
    """Compute a single named index from the stack (raises if bands missing)."""
    name = name.lower()
    spec = INDEX_REGISTRY.get(name)
    if spec is None:
        raise ValueError(f"Unknown index '{name}'. Known: {list(INDEX_REGISTRY)}")
    missing = [band for band in spec.bands if band not in stack.band_names]
    if missing:
        raise KeyError(f"Index '{name}' needs band(s) {missing}, missing from stack.")
    b = {band: stack.band(band).astype(np.float32) for band in spec.bands}
    return spec.fn(b).astype(np.float32)


def index_stats(index_map: np.ndarray) -> Dict:
    """Summary statistics for an index map, ignoring the exact-zero no-data."""
    valid = index_map[np.isfinite(index_map) & (index_map != 0)]
    if valid.size == 0:
        return {"count": 0}
    return {
        "count": int(valid.size),
        "min": round(float(valid.min()), 4),
        "max": round(float(valid.max()), 4),
        "mean": round(float(valid.mean()), 4),
        "median": round(float(np.median(valid)), 4),
        "std": round(float(valid.std()), 4),
    }


def colorize_index(index_map: np.ndarray, spec: Optional[IndexSpec] = None) -> np.ndarray:
    """Map an index to a red→yellow→green BGR image for visual QC.

    Scaled to the index's own [vmin, vmax] range. Red = low, green = high.
    """
    vmin, vmax = (spec.vmin, spec.vmax) if spec else (-1.0, 1.0)
    norm = np.clip((index_map - vmin) / (vmax - vmin + 1e-9), 0.0, 1.0)
    u8 = (norm * 255).astype(np.uint8)
    colored = cv2.applyColorMap(u8, cv2.COLORMAP_SUMMER)
    red_weight = (1.0 - norm)[..., None]
    red = np.zeros_like(colored)
    red[..., 2] = 255
    out = (colored * (1 - red_weight) + red * red_weight).astype(np.uint8)
    out[index_map == 0] = (128, 128, 128)
    return out


def compute_indices(
    stack: BandStack,
    names: Optional[List[str]] = None,
    output_dir: Optional[str] = None,
) -> Dict:
    """Compute several indices, optionally writing TIFF data + PNG previews.

    `names=None` computes every registry index the available bands support.
    Returns {index: {stats, meta, tiff?, preview?, _map}}; unavailable indices
    are silently skipped (see `available_indices` to know which).
    """
    if names is None:
        names = available_indices(stack.band_names)
    results: Dict[str, dict] = {}

    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    for name in names:
        name = name.lower()
        spec = INDEX_REGISTRY.get(name)
        if spec is None or not set(spec.bands).issubset(stack.band_names):
            continue  # skip unknown or uncomputable indices

        index_map = compute_index(stack, name)
        entry = {
            "stats": index_stats(index_map),
            "meta": {
                "name": spec.name, "formula": spec.formula,
                "category": spec.category, "description": spec.description,
                "higher_is_healthier": spec.higher_is_healthier,
            },
            "_map": index_map,
        }

        if output_dir:
            tiff = os.path.join(output_dir, f"{name}.tif")
            cv2.imwrite(tiff, index_map.astype(np.float32))
            preview = os.path.join(output_dir, f"{name}_preview.png")
            cv2.imwrite(preview, colorize_index(index_map, spec))
            entry["tiff"] = tiff
            entry["preview"] = preview

        results[name] = entry

    return results
