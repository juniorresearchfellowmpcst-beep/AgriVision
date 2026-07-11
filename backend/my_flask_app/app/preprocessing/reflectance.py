"""Radiometric correction: raw digital numbers (DN) -> surface reflectance.

Single-panel (reflectance-based) calibration, the standard field workflow:

  1. Normalise raw DN for the dark offset and, when metadata is available, for
     exposure time and gain so pixels are proportional to at-sensor radiance.
  2. From a photo of a panel of known reflectance, measure the mean panel
     signal per band -> gives a per-band scale factor
     F = panel_reflectance / panel_signal.
  3. Apply reflectance = F * normalised_scene_signal.

This assumes illumination is roughly constant between the panel shot and the
flight (the usual assumption for a single-panel calibration). If you have a
downwelling light sensor (DLS) or two panels, that data can be folded into the
per-band scale factor without changing the rest of the pipeline.
"""

from typing import Dict, Optional

import numpy as np

from .config import PipelineConfig
from .io import BandStack
from .panel import panel_signal


def normalise_dn(
    band_img: np.ndarray,
    black_level: float,
    exposure: Optional[float],
    gain: Optional[float],
) -> np.ndarray:
    """Dark-subtract and (if provided) exposure/gain-normalise raw DN.

    exposure/gain come from image metadata. When absent we simply dark-subtract,
    which is valid as long as the panel and scene were shot with the same
    camera settings.
    """
    out = band_img - float(black_level)
    np.clip(out, 0.0, None, out=out)  # negatives are just dark noise
    denom = 1.0
    if exposure:
        denom *= float(exposure)
    if gain:
        denom *= float(gain)
    if denom != 1.0 and denom > 0:
        out = out / denom
    return out


def pseudo_reflectance(scene_stack: BandStack) -> BandStack:
    """Rescale the stack to a relative 0..1 "pseudo-reflectance".

    Used when there is **no calibration panel** (e.g. images picked from disk).
    Critically, this uses a **single shared scale across all bands** (the global
    99.9th percentile), NOT an independent per-band stretch. A per-band stretch
    would flatten the NIR-vs-Red brightness gap that NDVI and every ratio index
    depend on, making them meaningless. A common divisor preserves inter-band
    ratios, so ratio/normalised-difference indices (NDVI, NDRE, ...) stay valid
    — they are invariant to a shared multiplicative factor anyway; the rescale
    only matters for soil-adjusted indices (SAVI, EVI) with additive constants.

    Results are *relative*, not physical reflectance — good for indices, zoning
    and risk, not for absolute cross-date comparison. Flagged `calibrated:false`.
    """
    data = scene_stack.data.astype(np.float32)
    # Common bright reference; ignore the dark tail and hot pixels.
    finite = data[np.isfinite(data)]
    hi = float(np.percentile(finite, 99.9)) if finite.size else 1.0
    if hi <= 0:
        hi = 1.0
    scaled = np.clip(data / hi, 0.0, 1.2).astype(np.float32)
    return BandStack(scaled, list(scene_stack.band_names))


def compute_scale_factors(
    panel_stack: BandStack,
    config: PipelineConfig,
    metadata: Optional[Dict[str, dict]] = None,
) -> Dict[str, dict]:
    """Derive the reflectance scale factor F for every band from the panel photo.

    metadata (optional) is {band: {"exposure": .., "gain": .., "black_level": ..}}.
    Returns {band: {scale, panel_signal, panel_reflectance, panel_info}}.
    """
    metadata = metadata or {}
    max_dn = config.max_dn()
    saturation_dn = config.sensor.saturation_fraction * max_dn

    results: Dict[str, dict] = {}
    for band in panel_stack.band_names:
        meta = metadata.get(band, {})
        black = meta.get("black_level", config.sensor.black_level.get(band, 0.0))

        raw = panel_stack.band(band)
        normalised = normalise_dn(
            raw, black, meta.get("exposure"), meta.get("gain")
        )

        roi = config.panel.roi.get(band) or config.panel.roi.get("all")
        signal, info = panel_signal(
            normalised, roi, config.panel.roi_shrink, saturation_dn=saturation_dn
        )

        reflectance = config.panel.reflectance.get(band)
        if reflectance is None:
            raise ValueError(f"No panel reflectance value configured for band '{band}'.")
        if signal <= 0:
            raise ValueError(
                f"Panel signal for band '{band}' is non-positive ({signal}); "
                "check the panel ROI and exposure."
            )

        results[band] = {
            "scale": reflectance / signal,
            "panel_signal": round(signal, 4),
            "panel_reflectance": reflectance,
            "panel_info": info,
        }
    return results


def apply_reflectance(
    scene_stack: BandStack,
    scale_factors: Dict[str, dict],
    config: PipelineConfig,
    metadata: Optional[Dict[str, dict]] = None,
) -> BandStack:
    """Convert a raw scene stack to a reflectance stack using the scale factors."""
    metadata = metadata or {}
    out_bands = []
    for band in scene_stack.band_names:
        if band not in scale_factors:
            raise KeyError(f"No scale factor computed for band '{band}'.")
        meta = metadata.get(band, {})
        black = meta.get("black_level", config.sensor.black_level.get(band, 0.0))

        normalised = normalise_dn(
            scene_stack.band(band), black, meta.get("exposure"), meta.get("gain")
        )
        reflectance = normalised * scale_factors[band]["scale"]
        np.clip(reflectance, 0.0, config.reflectance_clip, out=reflectance)
        out_bands.append(reflectance)

    return BandStack(np.stack(out_bands, axis=0), list(scene_stack.band_names))
