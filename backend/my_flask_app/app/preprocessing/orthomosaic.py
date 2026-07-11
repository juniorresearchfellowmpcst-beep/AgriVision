"""Stitching per-capture rasters into a single mosaic.

Scope and honesty about it: a true, metric **ortho**mosaic needs full
photogrammetry — camera poses, a digital surface model, and ground control /
RTK GPS — which is the job of dedicated engines (OpenDroneMap, Pix4D, Agisoft
Metashape). This module does two practical things instead:

  * `stitch_mosaic()` — a feature-based 2-D mosaic of overlapping nadir frames
    using OpenCV's stitcher. Over flat fields at consistent altitude this
    approximates an orthomosaic well enough for scouting and index maps, but it
    is **not** georeferenced and should not be used for survey-grade metrics.

  * `run_external_odm()` — a hook that hands the raw images to a real ODM engine
    when one is installed, and returns the georeferenced GeoTIFF it produces.

Feed the stitcher your reflectance-calibrated, band-aligned composites so the
mosaic inherits the radiometric correction.
"""

import os
import shutil
import subprocess
from typing import List, Optional

import cv2
import numpy as np


def stitch_mosaic(images: List[np.ndarray], try_scans_first: bool = True) -> np.ndarray:
    """Stitch overlapping frames into one mosaic image (BGR or grayscale in/out).

    `images` are 8-bit frames (e.g. false-colour composites of aligned bands).
    Returns the stitched mosaic. Raises RuntimeError on stitch failure with the
    OpenCV status code, which usually means too little overlap between frames.
    """
    if len(images) < 2:
        raise ValueError("Need at least two images to build a mosaic.")

    # SCANS mode (affine) suits near-nadir aerial frames; PANORAMA is the
    # fallback for scenes with more perspective.
    modes = [cv2.Stitcher_SCANS, cv2.Stitcher_PANORAMA]
    if not try_scans_first:
        modes.reverse()

    last_status = None
    for mode in modes:
        stitcher = cv2.Stitcher_create(mode)
        status, mosaic = stitcher.stitch(images)
        if status == cv2.Stitcher_OK:
            return mosaic
        last_status = status

    raise RuntimeError(
        f"OpenCV stitching failed (status={last_status}). "
        "Likely causes: insufficient overlap (<60%) or too few features. "
        "For survey-grade output use run_external_odm()."
    )


def odm_available() -> Optional[str]:
    """Return the ODM invocation that is available on this host, or None.

    Checks for a native `odm` binary first, then a docker image. This lets the
    service report the capability without running anything.
    """
    if shutil.which("odm"):
        return "odm"
    if shutil.which("docker"):
        return "docker:opendronemap/odm"
    return None


def run_external_odm(
    image_dir: str,
    project_dir: str,
    extra_args: Optional[List[str]] = None,
    timeout: Optional[int] = None,
) -> str:
    """Run OpenDroneMap over `image_dir` to produce a georeferenced orthophoto.

    Returns the path to the resulting orthophoto GeoTIFF. Raises RuntimeError if
    no ODM engine is installed or the run fails. This shells out to an external
    engine, so treat it as a long-running, resource-heavy operation.
    """
    engine = odm_available()
    if engine is None:
        raise RuntimeError(
            "No OpenDroneMap engine found. Install ODM natively or pull the "
            "opendronemap/odm docker image to enable georeferenced orthomosaics."
        )

    os.makedirs(project_dir, exist_ok=True)
    extra_args = extra_args or []

    if engine == "odm":
        cmd = ["odm", "--project-path", project_dir, "--images", image_dir, *extra_args]
    else:
        cmd = [
            "docker", "run", "--rm",
            "-v", f"{os.path.abspath(project_dir)}:/datasets/project",
            "-v", f"{os.path.abspath(image_dir)}:/datasets/project/images",
            "opendronemap/odm", "--project-path", "/datasets", "project", *extra_args,
        ]

    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError(f"ODM run failed:\n{proc.stderr[-2000:]}")

    ortho = os.path.join(project_dir, "odm_orthophoto", "odm_orthophoto.tif")
    if not os.path.isfile(ortho):
        raise RuntimeError("ODM finished but no orthophoto was produced.")
    return ortho
