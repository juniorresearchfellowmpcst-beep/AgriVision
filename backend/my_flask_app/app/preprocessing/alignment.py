"""Band co-registration ("do the bands line up cleanly?").

Multispectral cameras image each band through a separate lens, so the bands are
offset by parallax and small rotations/scales. Before you can compute any index
(NDVI, etc.) the bands must be warped onto a common frame, pixel-for-pixel.

Approach:
  * Align every band to a chosen reference band.
  * Primary estimator: ECC (cv2.findTransformECC) in a coarse-to-fine gaussian
    pyramid — robust to intensity differences between bands.
  * Fallback: ORB feature matching + RANSAC homography when ECC does not
    converge (e.g. very low-texture scenes).
  * Crop to the region valid in every band.
  * Score each band's alignment so the caller can verify it is clean.
"""

from typing import Dict, List, Tuple

import cv2
import numpy as np

from .config import AlignmentConfig
from .io import BandStack, to_uint8


_WARP_MODES = {
    "translation": cv2.MOTION_TRANSLATION,
    "euclidean": cv2.MOTION_EUCLIDEAN,
    "affine": cv2.MOTION_AFFINE,
    "homography": cv2.MOTION_HOMOGRAPHY,
}


def _prep(img: np.ndarray) -> np.ndarray:
    """8-bit, contrast-normalised, edge-emphasised view for matching.

    Bands differ in brightness (and some are inversely related), so we align on
    structure — the CLAHE-equalised gradient *magnitude*, which is invariant to
    the sign of the intensity relationship between bands.
    """
    u8 = to_uint8(img)
    u8 = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(u8)
    gx = cv2.Sobel(u8, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(u8, cv2.CV_32F, 0, 1, ksize=3)
    mag = cv2.magnitude(gx, gy)
    return to_uint8(mag)


def _score_map(img: np.ndarray) -> np.ndarray:
    """Blurred edge map used for the alignment score.

    Thin Sobel edges are extremely shift-sensitive — a 1-2px residual can drop
    their overlap to near zero. Blurring the magnitude thickens edges so the
    score measures whether structure *roughly* coincides (tolerant of small
    residuals) while still punishing gross misalignment.
    """
    return cv2.GaussianBlur(_prep(img).astype(np.float32), (0, 0), sigmaX=2.5)


def _pyramid_levels(shape: Tuple[int, int], requested: int) -> int:
    """Cap pyramid depth so the coarsest level stays usable (>= ~48 px)."""
    smallest = min(shape[0], shape[1])
    max_levels = 1
    while smallest // (2 ** max_levels) >= 48 and max_levels < requested:
        max_levels += 1
    return max(1, max_levels)


def _ecc_align(
    ref: np.ndarray, mov: np.ndarray, cfg: AlignmentConfig
) -> Tuple[np.ndarray, bool]:
    """Estimate the warp from `mov` to `ref` with pyramid ECC.

    Returns (warp_matrix, is_homography). Raises cv2.error if ECC fails.
    """
    mode = _WARP_MODES.get(cfg.warp_mode, cv2.MOTION_HOMOGRAPHY)
    is_h = mode == cv2.MOTION_HOMOGRAPHY

    # Align on the *blurred* gradient magnitude: sign-invariant across bands and
    # smooth enough that ECC's correlation basin can capture several-pixel
    # offsets instead of getting stuck on thin, sparse edges.
    ref_p, mov_p = _score_map(ref), _score_map(mov)

    # Build image pyramids, coarsest first. Depth is capped to the image size so
    # the coarsest level is not downsampled into uselessness.
    levels = _pyramid_levels(ref_p.shape, cfg.pyramid_levels)
    ref_pyr = [ref_p]
    mov_pyr = [mov_p]
    for _ in range(levels - 1):
        ref_pyr.append(cv2.pyrDown(ref_pyr[-1]))
        mov_pyr.append(cv2.pyrDown(mov_pyr[-1]))

    warp = np.eye(3, 3, dtype=np.float32) if is_h else np.eye(2, 3, dtype=np.float32)
    criteria = (
        cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT,
        cfg.ecc_iterations,
        cfg.ecc_epsilon,
    )

    # Coarse -> fine: scale the translation part of the warp up by 2 each step.
    for level in range(levels - 1, -1, -1):
        r, m = ref_pyr[level], mov_pyr[level]
        _, warp = cv2.findTransformECC(
            r, m, warp, mode, criteria, None, 5
        )
        if level > 0:
            if is_h:
                warp[0, 2] *= 2
                warp[1, 2] *= 2
            else:
                warp[0, 2] *= 2
                warp[1, 2] *= 2
    return warp, is_h


def _orb_homography(ref: np.ndarray, mov: np.ndarray) -> np.ndarray:
    """Fallback: feature-based homography from `mov` to `ref`."""
    ref_p, mov_p = _prep(ref), _prep(mov)
    orb = cv2.ORB_create(4000)
    k1, d1 = orb.detectAndCompute(ref_p, None)
    k2, d2 = orb.detectAndCompute(mov_p, None)
    if d1 is None or d2 is None or len(k1) < 8 or len(k2) < 8:
        raise ValueError("Not enough features for fallback alignment.")

    matcher = cv2.BFMatcher(cv2.NORM_HAMMING)
    matches = matcher.knnMatch(d2, d1, k=2)
    good = [m for pair in matches if len(pair) == 2 for m, n in [pair] if m.distance < 0.75 * n.distance]
    if len(good) < 8:
        raise ValueError("Too few good feature matches for fallback alignment.")

    src = np.float32([k2[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
    dst = np.float32([k1[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
    H, _ = cv2.findHomography(src, dst, cv2.RANSAC, 3.0)
    if H is None:
        raise ValueError("Fallback homography estimation failed.")
    return H.astype(np.float32)


def _warp(
    img: np.ndarray,
    warp: np.ndarray,
    is_h: bool,
    size: Tuple[int, int],
    inverse: bool = False,
) -> np.ndarray:
    """Resample `img` through `warp`.

    Convention matters: cv2.findTransformECC returns a warp that samples the
    moving image at ref coordinates, so it must be applied with
    WARP_INVERSE_MAP. A findHomography(mov_pts, ref_pts) matrix maps mov→ref
    and is applied forward (default flags).

    Image data is warped with BORDER_REPLICATE so no artificial black border
    edge is created (it would poison the gradient-based alignment score);
    actual validity is tracked separately via the mask, which must be warped
    with the default constant-0 border.
    """
    w, h = size
    flags = cv2.INTER_LINEAR | (cv2.WARP_INVERSE_MAP if inverse else 0)
    if is_h:
        return cv2.warpPerspective(
            img, warp, (w, h), flags=flags, borderMode=cv2.BORDER_REPLICATE
        )
    return cv2.warpAffine(
        img, warp, (w, h), flags=flags, borderMode=cv2.BORDER_REPLICATE
    )


def _warp_mask(
    mask: np.ndarray,
    warp: np.ndarray,
    is_h: bool,
    size: Tuple[int, int],
    inverse: bool,
) -> np.ndarray:
    """Warp a validity mask with constant-0 border (out-of-frame == invalid)."""
    w, h = size
    flags = cv2.INTER_NEAREST | (cv2.WARP_INVERSE_MAP if inverse else 0)
    if is_h:
        return cv2.warpPerspective(mask, warp, (w, h), flags=flags, borderValue=0)
    return cv2.warpAffine(mask, warp, (w, h), flags=flags, borderValue=0)


def _alignment_score(ref: np.ndarray, mov: np.ndarray) -> float:
    """Structural agreement between two bands in [0, 1].

    Zero-normalised cross-correlation of the (blurred) edge maps: 1.0 ==
    structure lines up perfectly, ~0 == unrelated. This is the number that
    answers "do the bands line up cleanly?". A border margin is excluded so
    warp edge effects don't skew the comparison.
    """
    a = _score_map(ref)
    b = _score_map(mov)
    # Ignore the outer 4% (min 8 px) where warping artefacts live.
    my = max(8, int(a.shape[0] * 0.04))
    mx = max(8, int(a.shape[1] * 0.04))
    if a.shape[0] > 2 * my and a.shape[1] > 2 * mx:
        a = a[my:-my, mx:-mx]
        b = b[my:-my, mx:-mx]
    a = a - a.mean()
    b = b - b.mean()
    denom = np.sqrt((a * a).sum() * (b * b).sum())
    if denom == 0:
        return 0.0
    return float(np.clip((a * b).sum() / denom, 0.0, 1.0))


def align_stack(stack: BandStack, cfg: AlignmentConfig) -> Tuple[BandStack, Dict]:
    """Co-register every band to the reference band.

    Returns (aligned_stack, report). The report has per-band method + score and
    an overall `aligned_cleanly` flag against cfg.min_alignment_score.
    """
    if cfg.reference_band not in stack.band_names:
        raise KeyError(
            f"Reference band '{cfg.reference_band}' not in stack {stack.band_names}"
        )

    ref_idx = stack.index(cfg.reference_band)
    ref = stack.data[ref_idx]
    h, w = ref.shape
    size = (w, h)

    aligned: List[np.ndarray] = [None] * len(stack.band_names)
    aligned[ref_idx] = ref.copy()
    # Track where each warped band has valid (in-frame) data, to crop later.
    valid = np.ones((h, w), dtype=np.uint8)
    per_band: Dict[str, dict] = {}

    for i, band in enumerate(stack.band_names):
        if i == ref_idx:
            per_band[band] = {"method": "reference", "score_before": 1.0, "score_after": 1.0}
            continue

        mov = stack.data[i]
        before = _alignment_score(ref, mov)

        # Try ECC, then ORB as a fallback; keep whichever candidate scores best,
        # and never accept a warp that is worse than leaving the band as-is.
        # ECC warps sample ref→mov and need the inverse flag; ORB maps mov→ref.
        best = None  # (warp, is_h, inverse)
        best_score, best_method = before, "identity"
        for method in ("ecc", "orb_fallback"):
            try:
                if method == "ecc":
                    warp, is_h = _ecc_align(ref, mov, cfg)
                    inverse = True
                else:
                    warp, is_h, inverse = _orb_homography(ref, mov), True, False
            except (cv2.error, ValueError):
                continue
            candidate = _warp(mov, warp, is_h, size, inverse)
            score = _alignment_score(ref, candidate)
            if score > best_score:
                best, best_score, best_method = (warp, is_h, inverse), score, method

        if best is None:
            # No estimate beat the identity — leave the band unwarped.
            warped = mov
            mask = np.ones(mov.shape, dtype=np.uint8)
        else:
            warp, is_h, inverse = best
            warped = _warp(mov, warp, is_h, size, inverse)
            mask = _warp_mask(np.ones_like(mov, dtype=np.uint8), warp, is_h, size, inverse)

        valid &= (mask > 0).astype(np.uint8)
        aligned[i] = warped
        per_band[band] = {
            "method": best_method,
            "score_before": round(before, 4),
            "score_after": round(best_score, 4),
        }

    aligned_stack = BandStack(np.stack(aligned, axis=0), list(stack.band_names))

    # Crop everything to the common valid region so no band has border gaps.
    crop = _valid_bbox(valid)
    if crop is not None:
        x, y, cw, ch = crop
        aligned_stack = BandStack(
            aligned_stack.data[:, y:y + ch, x:x + cw], list(stack.band_names)
        )

    scores = [v["score_after"] for v in per_band.values()]
    report = {
        "reference_band": cfg.reference_band,
        "warp_mode": cfg.warp_mode,
        "per_band": per_band,
        "min_score": round(min(scores), 4),
        "mean_score": round(float(np.mean(scores)), 4),
        "aligned_cleanly": bool(min(scores) >= cfg.min_alignment_score),
        "crop": list(crop) if crop else None,
        "output_shape": list(aligned_stack.data.shape),
    }
    return aligned_stack, report


def _valid_bbox(mask: np.ndarray) -> Tuple[int, int, int, int]:
    """Largest axis-aligned bbox where the mask is fully valid (approximate).

    Uses the intersection of valid rows/cols, which is exact for the common
    case of translations/small warps and a safe (never-too-large) crop otherwise.
    """
    rows = np.where(mask.all(axis=1))[0]
    cols = np.where(mask.all(axis=0))[0]
    if rows.size == 0 or cols.size == 0:
        # Fall back to any-valid columns/rows so we don't return an empty crop.
        rows = np.where(mask.any(axis=1))[0]
        cols = np.where(mask.any(axis=0))[0]
        if rows.size == 0 or cols.size == 0:
            return None
    y0, y1 = rows[0], rows[-1]
    x0, x1 = cols[0], cols[-1]
    return int(x0), int(y0), int(x1 - x0 + 1), int(y1 - y0 + 1)
