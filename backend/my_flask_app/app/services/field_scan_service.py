"""Service layer for the weed + disease field scan.

Two ways in, one engine behind them:

  * ``analyze`` — a single frame the app already has (a photo, or one frame
    pulled off the RGB feed). The quick "what is this?" answer.
  * ``scan_session`` — every RGB frame a low-pace mission recorded, scanned in
    order and rolled up into one answer about the field. This is the mode the
    feature is really for: one frame is an anecdote, a pass is evidence.

Both persist per-frame rows (see :class:`app.api.models.field_scan.
FieldScanRecord`) so the field-level summary can be recomputed later, and so a
hotspot keeps the coordinates a spray run would need.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict, List, Optional, Tuple

import cv2

from app.ai import crop_model, field_scan
from app.ai.crop_kb import get_crop, list_crops
from app.ai.weed_kb import list_weeds
from app.api.models.field_scan import FieldScanRecord
from app.capture import absolute as capture_absolute
from app.capture import safe_key
from app.repositories.capture_repository import CaptureFrameRepository
from app.repositories.field_scan_repository import FieldScanRepository

logger = logging.getLogger(__name__)

# Phone photos are a few MB; anything far bigger is a mistake, not a frame.
_MAX_UPLOAD_BYTES = 16 * 1024 * 1024

# A low pass can record hundreds of frames. Scanning them all in one request
# would time the app out, so the batch is capped and the response says how
# many are left.
_MAX_FRAMES_PER_SCAN = 40


def _fail(message: str, status: int = 400) -> Tuple[Dict[str, Any], int]:
    return {"status": "error", "message": message}, status


class FieldScanService:

    # ── capabilities ──────────────────────────────────────────────────────

    @staticmethod
    def capabilities() -> Tuple[Dict[str, Any], int]:
        engines = crop_model.engines()
        return {
            "status": "ok",
            "feature": "field-scan-weed-and-disease",
            "engines": engines,
            "crops": list_crops(),
            "weed_types": ["grass", "sedge", "broadleaf"],
            "weed_methods": ["inter-row", "appearance", "inconclusive"],
            "region": "Madhya Pradesh cropping system",
            "note": (
                "Runs on OpenCV heuristics out of the box. Point "
                "AI_CROP_MODEL_PATH / AI_WEED_MODEL_PATH at TorchScript models "
                "to switch either half to a trained CNN — see "
                "docs/CROP_CNN_TRAINING.md."
            ),
        }, 200

    @staticmethod
    def catalog(crop: Optional[str] = None) -> Tuple[Dict[str, Any], int]:
        """Crops and their diseases, plus the weeds that go with them."""
        crop_entry = get_crop(crop)
        if crop and not crop_entry:
            return _fail(f"Unknown crop '{crop}'.", 404)

        if crop_entry:
            return {
                "status": "ok",
                "crop": {
                    "id": crop_entry["id"],
                    "name": crop_entry["name"],
                    "local_name": crop_entry.get("local_name", ""),
                    "season": crop_entry.get("season", ""),
                    "note": crop_entry.get("note", ""),
                },
                "diseases": crop_entry["diseases"],
                "weeds": list_weeds(crop_entry["id"]),
            }, 200

        return {
            "status": "ok",
            "crops": list_crops(),
            "weeds": list_weeds(),
        }, 200

    # ── one frame ─────────────────────────────────────────────────────────

    @staticmethod
    def analyze(
        image_bytes: bytes,
        crop: Optional[str],
        output_base: str,
        url_prefix: str,
        filename: Optional[str] = None,
        user_id: Optional[int] = None,
        field_name: Optional[str] = None,
        lat: Optional[float] = None,
        lon: Optional[float] = None,
        target: str = "both",
    ) -> Tuple[Dict[str, Any], int]:
        """Scan one uploaded canopy frame for weeds and disease.

        ``target`` narrows what runs: ``"weed"`` for a weed-detection pass,
        ``"disease"`` for a leaf diagnosis, ``"both"`` for everything.
        """
        if not image_bytes:
            return _fail("Attach a photo of the crop canopy.")
        if len(image_bytes) > _MAX_UPLOAD_BYTES:
            return _fail("Image is too large. Please send a frame under 16 MB.")

        image = field_scan.decode(image_bytes)
        if image is None:
            return _fail(
                "Could not read the image. Send a clear JPG or PNG frame of the "
                "crop canopy."
            )

        result = field_scan.scan_frame(image, crop=crop, target=target)
        if result.get("status") != "ok":
            return result, 400

        record = FieldScanService._persist(
            result,
            output_base=output_base,
            url_prefix=url_prefix,
            user_id=user_id,
            field_name=field_name,
            filename=filename,
            lat=lat,
            lon=lon,
        )
        result.pop("_overlay", None)
        if record is not None:
            result["scan_id"] = record.id
            if record.overlay_path:
                result["overlay_url"] = (
                    f"{url_prefix.rstrip('/')}/{record.overlay_path}"
                )
            result["created_at"] = (
                record.created_at.isoformat() if record.created_at else None
            )
        return result, 200

    # ── a whole low-pace pass ─────────────────────────────────────────────

    @staticmethod
    def scan_session(
        payload: Dict,
        capture_base: str,
        output_base: str,
        url_prefix: str,
        user_id: Optional[int] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Scan every RGB frame from a capture session and summarise the field.

        Payload: ``{"session_id": "...", "crop": "soybean", "limit": 40}``
        """
        payload = payload if isinstance(payload, dict) else {}

        session_id = str(payload.get("session_id") or "").strip()
        if not session_id:
            return _fail("Which pass? Send the 'session_id' of a capture session.")

        crop = payload.get("crop")
        if crop and not get_crop(crop):
            return _fail(f"Unknown crop '{crop}'.")

        target = str(payload.get("target") or "both").strip().lower()
        if target not in field_scan.SCAN_TARGETS:
            return _fail(
                "target must be one of: " + ", ".join(field_scan.SCAN_TARGETS) + "."
            )

        try:
            limit = min(int(payload.get("limit") or _MAX_FRAMES_PER_SCAN), _MAX_FRAMES_PER_SCAN)
        except (TypeError, ValueError):
            limit = _MAX_FRAMES_PER_SCAN

        frames = CaptureFrameRepository.list_frames(
            user_id=user_id, session_id=session_id, role="rgb", limit=200
        )
        if not frames:
            return _fail(
                "That session has no RGB frames. The weed/disease scan reads "
                "the normal camera, not the multispectral bands — fly the low "
                "pass with the RGB feed enabled.",
                409,
            )

        # Oldest first: a pass reads as a flight line, not a reverse-ordered
        # list, and the aggregate's hotspot order should follow the ground.
        frames = list(reversed(frames))
        selected = frames[:limit]

        scans: List[Dict[str, Any]] = []
        # (scan payload, its unsaved row) — paired explicitly rather than
        # zipped later, because a frame whose row could not be built would
        # silently shift every later scan's id onto the wrong frame.
        pending: List[Tuple[Dict[str, Any], FieldScanRecord]] = []
        errors: List[Dict[str, str]] = []

        for frame in selected:
            path = capture_absolute(frame.path, capture_base)
            image = cv2.imread(path, cv2.IMREAD_COLOR)
            if image is None:
                errors.append({"frame_id": frame.id, "message": f"Could not read {frame.path}."})
                continue

            result = field_scan.scan_frame(image, crop=crop, target=target)
            if result.get("status") != "ok":
                errors.append({"frame_id": frame.id, "message": result.get("message", "Scan failed.")})
                continue

            result["frame_id"] = frame.id
            result["lat"] = frame.lat
            result["lon"] = frame.lon

            record = FieldScanService._persist(
                result,
                output_base=output_base,
                url_prefix=url_prefix,
                user_id=user_id,
                field_name=frame.field_name,
                filename=os.path.basename(frame.path),
                lat=frame.lat,
                lon=frame.lon,
                session_id=frame.session_id,
                shot_id=frame.shot_id,
                frame_id=frame.id,
                commit=False,
            )
            if record is not None:
                pending.append((result, record))
                result["overlay_path"] = record.overlay_path

            result.pop("_overlay", None)
            scans.append(result)

        if pending:
            try:
                FieldScanRepository.create_many([record for _scan, record in pending])
                for scan, record in pending:
                    scan["scan_id"] = record.id
            except Exception as exc:  # pragma: no cover - defensive
                logger.warning("Could not record field scans: %s", exc)

        if not scans:
            return {
                "status": "error",
                "message": "None of the frames in that session could be scanned.",
                "errors": errors,
            }, 400

        summary = field_scan.aggregate(scans, crop=crop)
        prefix = url_prefix.rstrip("/")
        for scan in scans:
            if scan.get("overlay_path"):
                scan["overlay_url"] = f"{prefix}/{scan['overlay_path']}"

        return {
            "status": "ok",
            "message": f"Scanned {len(scans)} frame(s) from {session_id}.",
            "session_id": session_id,
            "crop": crop,
            "target": target,
            "summary": summary,
            "frames": scans,
            "frames_available": len(frames),
            "frames_remaining": max(0, len(frames) - len(selected)),
            "errors": errors,
        }, 200

    # ── persistence ───────────────────────────────────────────────────────

    @staticmethod
    def _persist(
        result: Dict[str, Any],
        output_base: str,
        url_prefix: str,
        user_id: Optional[int],
        field_name: Optional[str],
        filename: Optional[str],
        lat: Optional[float] = None,
        lon: Optional[float] = None,
        session_id: Optional[str] = None,
        shot_id: Optional[str] = None,
        frame_id: Optional[int] = None,
        commit: bool = True,
    ) -> Optional[FieldScanRecord]:
        """Write the overlay and the scan row. Never fails the scan itself —
        the operator still gets their answer, we just lose the history."""
        overlay_path = None
        try:
            overlay = result.get("_overlay")
            if overlay is not None:
                overlay_path = FieldScanService._write_overlay(
                    overlay, output_base, session_id, frame_id, filename
                )
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Could not write scan overlay: %s", exc)

        try:
            disease = result.get("disease") or {}
            weeds = result.get("weeds") or {}
            pressure = weeds.get("pressure") or {}
            record = FieldScanRecord(
                user_id=user_id,
                session_id=session_id,
                shot_id=shot_id,
                frame_id=frame_id,
                crop=result.get("crop"),
                condition_id=disease.get("id"),
                condition_name=disease.get("name"),
                severity=(result.get("severity") or {}).get("level"),
                confidence=float(disease.get("confidence") or 0.0),
                engine=disease.get("source"),
                is_healthy=bool(result.get("is_healthy")),
                weed_coverage=float(weeds.get("weed_coverage") or 0.0),
                weed_pressure=pressure.get("level"),
                weed_method=weeds.get("method"),
                lat=lat,
                lon=lon,
                overlay_path=overlay_path,
                filename=filename,
                field_name=field_name,
                detail=json.dumps({k: v for k, v in result.items() if not k.startswith("_")}),
            )
            if not commit:
                return record
            return FieldScanRepository.create(record)
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Could not record field scan: %s", exc)
            return None

    @staticmethod
    def _write_overlay(
        overlay,
        output_base: str,
        session_id: Optional[str],
        frame_id: Optional[int],
        filename: Optional[str],
    ) -> Optional[str]:
        import time
        import uuid

        folder = safe_key(session_id or "single", "single")
        directory = os.path.join(output_base, folder)
        os.makedirs(directory, exist_ok=True)

        stem = (
            f"frame_{frame_id}"
            if frame_id is not None
            else f"scan_{int(time.time())}_{uuid.uuid4().hex[:4]}"
        )
        path = os.path.join(directory, f"{stem}_weeds.jpg")
        if not cv2.imwrite(path, overlay):
            return None
        return f"{folder}/{os.path.basename(path)}"

    # ── history ───────────────────────────────────────────────────────────

    @staticmethod
    def list_scans(
        user_id: Optional[int] = None,
        session_id: Optional[str] = None,
        crop: Optional[str] = None,
        url_prefix: str = "",
    ) -> Tuple[Dict[str, Any], int]:
        scans = FieldScanRepository.list_scans(
            user_id=user_id, session_id=session_id, crop=crop
        )
        return {
            "status": "ok",
            "scans": [s.to_dict(url_prefix=url_prefix) for s in scans],
            "sessions": FieldScanRepository.list_sessions(user_id=user_id),
            "unhealthy_count": sum(1 for s in scans if not s.is_healthy),
        }, 200

    @staticmethod
    def get_scan(
        scan_id: int, user_id: Optional[int] = None, url_prefix: str = ""
    ) -> Tuple[Dict[str, Any], int]:
        scan = FieldScanRepository.get_by_id(scan_id)
        if scan is None:
            return _fail("Scan not found.", 404)
        if scan.user_id is not None and user_id is not None and scan.user_id != user_id:
            return _fail("Not your scan.", 403)
        return {
            "status": "ok",
            "scan": scan.to_dict(include_detail=True, url_prefix=url_prefix),
        }, 200

    @staticmethod
    def summary(
        session_id: str, user_id: Optional[int] = None
    ) -> Tuple[Dict[str, Any], int]:
        """Re-derive the field-level answer from stored per-frame scans.

        Cheap, because it reads the saved verdicts rather than re-running the
        CNN over the whole pass.
        """
        if not session_id:
            return _fail("Send a 'session_id'.")

        rows = FieldScanRepository.list_scans(user_id=user_id, session_id=session_id)
        if not rows:
            return _fail("No scans recorded for that session.", 404)

        scans = []
        for row in rows:
            detail = row.detail_dict()
            if detail:
                detail.setdefault("frame_id", row.frame_id)
                detail.setdefault("lat", row.lat)
                detail.setdefault("lon", row.lon)
                scans.append(detail)

        if not scans:
            return _fail("Stored scans have no detail to summarise.", 409)

        crop = next((row.crop for row in rows if row.crop), None)
        return {
            "status": "ok",
            "session_id": session_id,
            "summary": field_scan.aggregate(scans, crop=crop),
        }, 200
