"""Service layer for live camera capture.

Owns the flow the operator sees as one button press:

    "Capture"  ->  grab every enabled camera at once
               ->  stamp each frame with the aircraft's position
               ->  write the files + rows that the spray prescription and the
                   weed/disease scan read afterwards

Static methods returning ``(response_dict, status_code)``, like the other
services. Cameras are registered by the operator — nothing is seeded, because
a camera that does not exist cannot take a picture, and a fake one in the list
is worse than an empty list.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

from app.api.models.capture import CAMERA_ROLES, CameraFeed, CaptureFrame
from app.capture import (
    grab_many,
    new_session_id,
    new_shot_id,
    probe,
    safe_key,
    save_frame,
    telemetry_geotag,
)
from app.preprocessing.config import DEFAULT_BANDS
from app.repositories.capture_repository import (
    CameraRepository,
    CaptureFrameRepository,
)

logger = logging.getLogger(__name__)


def _fail(message: str, status: int = 400) -> Tuple[Dict[str, Any], int]:
    return {"status": "error", "message": message}, status


class CaptureService:

    # ── capabilities ──────────────────────────────────────────────────────

    @staticmethod
    def capabilities() -> Tuple[Dict[str, Any], int]:
        return {
            "status": "ok",
            "feature": "drone-camera-capture",
            "roles": list(CAMERA_ROLES),
            "bands": list(DEFAULT_BANDS),
            "transports": ["rtsp", "http-mjpeg", "http-snapshot", "local-file"],
            # What the app checks before offering the live view at all, so a
            # build talking to an older backend degrades to stills instead of
            # showing a video pane that can never fill.
            "live": {
                "supported": True,
                "relay": "mjpeg",
                "stream_path": "/api/capture/cameras/{camera_id}/stream",
                "frame_path": "/api/capture/cameras/{camera_id}/frame",
                "analysis_path": "/api/capture/cameras/{camera_id}/analyze",
                "analysis_roles": ["rgb"],
            },
            "note": "Multispectral rigs register one camera per band; the RGB "
                    "IP camera registers one camera with no band.",
        }, 200

    # ── camera registry ───────────────────────────────────────────────────

    @staticmethod
    def list_cameras(user_id: Optional[int] = None) -> Tuple[Dict[str, Any], int]:
        cameras = CameraRepository.list_cameras(user_id=user_id)
        multispectral = [c for c in cameras if c.role == "multispectral" and c.enabled]
        return {
            "status": "ok",
            "cameras": [c.to_dict() for c in cameras],
            # What the app needs to know before offering "Capture": a spray
            # prescription needs at least red + NIR to compute an index at all.
            "multispectral_bands": sorted(
                {c.band for c in multispectral if c.band}
            ),
            "ready_for_multispectral": bool(
                {"red", "nir"}.issubset({c.band for c in multispectral})
            ),
            "has_rgb": any(c.role == "rgb" and c.enabled for c in cameras),
        }, 200

    @staticmethod
    def add_camera(payload: Dict, user_id: Optional[int] = None) -> Tuple[Dict, int]:
        payload = payload if isinstance(payload, dict) else {}

        url = str(payload.get("url") or "").strip()
        if not url:
            return _fail("A camera needs a stream or snapshot URL.")

        role = str(payload.get("role") or "rgb").strip().lower()
        if role not in CAMERA_ROLES:
            return _fail(f"role must be one of: {', '.join(CAMERA_ROLES)}.")

        band = payload.get("band")
        band = safe_key(band, "") if band else None
        if role == "multispectral":
            if not band:
                return _fail(
                    "A multispectral camera must say which band it sees "
                    f"({', '.join(DEFAULT_BANDS)})."
                )
            if band not in DEFAULT_BANDS:
                return _fail(
                    f"Unknown band '{band}'. Expected one of: "
                    f"{', '.join(DEFAULT_BANDS)}."
                )
        else:
            band = None

        fov = payload.get("fov_deg")
        try:
            fov = float(fov) if fov not in (None, "") else None
        except (TypeError, ValueError):
            return _fail("fov_deg must be a number (the camera's horizontal FOV).")
        if fov is not None and not 5.0 < fov < 175.0:
            return _fail("fov_deg should be between 5 and 175 degrees.")

        camera = CameraFeed(
            user_id=user_id,
            name=str(payload.get("name") or "").strip() or f"{role} camera",
            role=role,
            band=band,
            url=url,
            fov_deg=fov,
            enabled=bool(payload.get("enabled", True)),
        )
        CameraRepository.create(camera)
        return {"status": "ok", "message": "Camera added.", "camera": camera.to_dict()}, 201

    @staticmethod
    def update_camera(
        camera_id: int, payload: Dict, user_id: Optional[int] = None
    ) -> Tuple[Dict, int]:
        camera, error = CaptureService.resolve_camera(camera_id, user_id)
        if error:
            return error

        payload = payload if isinstance(payload, dict) else {}
        if "name" in payload:
            camera.name = str(payload["name"]).strip() or camera.name
        if "url" in payload and str(payload["url"]).strip():
            camera.url = str(payload["url"]).strip()
        if "enabled" in payload:
            camera.enabled = bool(payload["enabled"])
        if "band" in payload and camera.role == "multispectral":
            band = safe_key(payload["band"], "")
            if band not in DEFAULT_BANDS:
                return _fail(f"Unknown band '{payload['band']}'.")
            camera.band = band
        if "fov_deg" in payload:
            try:
                camera.fov_deg = (
                    float(payload["fov_deg"]) if payload["fov_deg"] not in (None, "") else None
                )
            except (TypeError, ValueError):
                return _fail("fov_deg must be a number.")

        CameraRepository.save()
        return {"status": "ok", "message": "Camera updated.", "camera": camera.to_dict()}, 200

    @staticmethod
    def resolve_camera(
        camera_id: int, user_id: Optional[int] = None
    ) -> Tuple[Optional[CameraFeed], Optional[Tuple[Dict, int]]]:
        """``(camera, None)`` or ``(None, error_response)``.

        Anonymous rows (``user_id`` NULL) belong to everyone, matching the
        drone/mission rule: a camera registered before anyone signed in is
        still the aircraft's camera.
        """
        camera = CameraRepository.get_by_id(camera_id)
        if camera is None:
            return None, _fail("Camera not found.", 404)
        if camera.user_id is not None and user_id is not None and camera.user_id != user_id:
            return None, _fail("Not your camera.", 403)
        return camera, None

    @staticmethod
    def delete_camera(camera_id: int, user_id: Optional[int] = None) -> Tuple[Dict, int]:
        camera, error = CaptureService.resolve_camera(camera_id, user_id)
        if error:
            return error
        # A camera being removed must not leave its live session running: the
        # hub is keyed by id, and the next camera to reuse that id would
        # inherit a reader thread still pointed at the old URL.
        from app.capture.live import hub
        from app.services.live_analysis import manager as live_analysis

        live_analysis.stop(str(camera_id))
        hub.close(str(camera_id))

        CameraRepository.delete(camera)
        return {"status": "ok", "message": "Camera removed."}, 200

    @staticmethod
    def test_camera(
        camera_id: Optional[int] = None,
        url: Optional[str] = None,
        user_id: Optional[int] = None,
    ) -> Tuple[Dict, int]:
        """Is this feed actually live? Answers 200 either way — 'the camera is
        unreachable' is information, not a server error."""
        if camera_id is not None:
            camera = CameraRepository.get_by_id(camera_id)
            if camera is None:
                return _fail("Camera not found.", 404)
            url = camera.url
        if not url:
            return _fail("Give a camera_id or a url to test.")

        result = probe(url)
        return {"status": "ok", **result}, 200

    # ── capture ───────────────────────────────────────────────────────────

    @staticmethod
    def shoot(
        base_dir: str,
        session_id: Optional[str] = None,
        camera_ids: Optional[List[int]] = None,
        field_name: Optional[str] = None,
        user_id: Optional[int] = None,
        url_prefix: str = "",
    ) -> Tuple[Dict[str, Any], int]:
        """Trigger every selected camera once and store what comes back.

        All feeds are pulled in parallel: five bands grabbed one after another
        would spread a single "shot" across seconds of forward flight, and the
        bands would no longer describe the same patch of ground.
        """
        cameras = CameraRepository.list_cameras(user_id=user_id, enabled_only=True)
        if camera_ids:
            wanted = {int(c) for c in camera_ids}
            cameras = [c for c in cameras if c.id in wanted]
        if not cameras:
            return _fail(
                "No cameras are configured. Add the drone's multispectral band "
                "feeds and its RGB camera before capturing.",
                409,
            )

        session_id = session_id or new_session_id()
        shot_id = new_shot_id()

        # Position first: the geotag should describe where the aircraft was
        # when the shutter fired, not where it had drifted to once five
        # network round-trips had finished.
        geotag = telemetry_geotag()

        feeds = [(CaptureService._frame_key(c), c.url) for c in cameras]
        frames, errors = grab_many(feeds)

        by_key = {CaptureService._frame_key(c): c for c in cameras}
        rows: List[CaptureFrame] = []
        for key, frame in frames.items():
            camera = by_key[key]
            try:
                stored = save_frame(frame, base_dir, session_id, shot_id, key)
            except Exception as exc:
                errors[key] = f"Could not save the frame: {exc}"
                continue

            height, width = frame.shape[:2]
            rows.append(
                CaptureFrame(
                    user_id=user_id,
                    camera_id=camera.id,
                    session_id=session_id,
                    shot_id=shot_id,
                    role=camera.role,
                    band=camera.band,
                    path=stored["path"],
                    preview_path=stored.get("preview"),
                    width=int(width),
                    height=int(height),
                    lat=geotag.get("lat"),
                    lon=geotag.get("lon"),
                    alt_m=geotag.get("alt_m"),
                    heading_deg=geotag.get("heading_deg"),
                    field_name=field_name,
                )
            )

        if not rows:
            return {
                "status": "error",
                "message": "No camera returned a frame.",
                "errors": errors,
            }, 502

        CaptureFrameRepository.create_many(rows)

        bands = sorted({r.band for r in rows if r.band})
        return {
            "status": "ok",
            "message": f"Captured {len(rows)} frame(s).",
            "session_id": session_id,
            "shot_id": shot_id,
            "frames": [r.to_dict(url_prefix=url_prefix) for r in rows],
            "bands": bands,
            "geotag": geotag,
            "has_fix": geotag.get("lat") is not None,
            # The prescription needs a red + NIR pair at minimum; say so now
            # rather than after the operator has flown the whole block.
            "analysable": bool({"red", "nir"}.issubset(set(bands))),
            "errors": errors,
        }, 200

    @staticmethod
    def _frame_key(camera: CameraFeed) -> str:
        """Filename stem for a camera's frame within a shot."""
        if camera.role == "multispectral" and camera.band:
            return safe_key(camera.band)
        return safe_key(camera.name, "rgb") if camera.role != "rgb" else "rgb"

    @staticmethod
    def store_uploaded(
        base_dir: str,
        files: List[Tuple[str, str, bytes]],
        session_id: Optional[str] = None,
        field_name: Optional[str] = None,
        user_id: Optional[int] = None,
        url_prefix: str = "",
        geotag: Optional[Dict[str, float]] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Store frames the app already holds, as if they had been captured.

        This is the path for a rig that records to a card instead of streaming,
        and for testing the whole prescription chain on a desk with no cameras
        attached. ``files`` is ``[(key, filename, bytes)]`` where *key* is the
        band name (multispectral) or "rgb".
        """
        import cv2
        import numpy as np

        if not files:
            return _fail("Attach at least one image.")

        session_id = session_id or new_session_id("upload")
        shot_id = new_shot_id()
        geotag = geotag or telemetry_geotag()

        rows: List[CaptureFrame] = []
        errors: Dict[str, str] = {}
        for key, filename, data in files:
            key = safe_key(key, "rgb")
            frame = cv2.imdecode(
                np.frombuffer(data, dtype=np.uint8),
                cv2.IMREAD_ANYDEPTH | cv2.IMREAD_UNCHANGED,
            )
            if frame is None:
                errors[key] = f"Could not decode {filename or key}."
                continue

            try:
                stored = save_frame(frame, base_dir, session_id, shot_id, key)
            except Exception as exc:
                errors[key] = f"Could not save {filename or key}: {exc}"
                continue

            height, width = frame.shape[:2]
            is_band = key in DEFAULT_BANDS
            rows.append(
                CaptureFrame(
                    user_id=user_id,
                    session_id=session_id,
                    shot_id=shot_id,
                    role="multispectral" if is_band else "rgb",
                    band=key if is_band else None,
                    path=stored["path"],
                    preview_path=stored.get("preview"),
                    width=int(width),
                    height=int(height),
                    lat=geotag.get("lat"),
                    lon=geotag.get("lon"),
                    alt_m=geotag.get("alt_m"),
                    heading_deg=geotag.get("heading_deg"),
                    field_name=field_name,
                )
            )

        if not rows:
            return {
                "status": "error",
                "message": "None of the uploaded files could be read.",
                "errors": errors,
            }, 400

        CaptureFrameRepository.create_many(rows)
        bands = sorted({r.band for r in rows if r.band})
        return {
            "status": "ok",
            "message": f"Stored {len(rows)} frame(s).",
            "session_id": session_id,
            "shot_id": shot_id,
            "frames": [r.to_dict(url_prefix=url_prefix) for r in rows],
            "bands": bands,
            "analysable": bool({"red", "nir"}.issubset(set(bands))),
            "errors": errors,
        }, 200

    # ── history ───────────────────────────────────────────────────────────

    @staticmethod
    def list_sessions(user_id: Optional[int] = None) -> Tuple[Dict, int]:
        return {
            "status": "ok",
            "sessions": CaptureFrameRepository.list_sessions(user_id=user_id),
        }, 200

    @staticmethod
    def list_frames(
        user_id: Optional[int] = None,
        session_id: Optional[str] = None,
        shot_id: Optional[str] = None,
        role: Optional[str] = None,
        url_prefix: str = "",
    ) -> Tuple[Dict, int]:
        frames = CaptureFrameRepository.list_frames(
            user_id=user_id, session_id=session_id, shot_id=shot_id, role=role
        )
        # Group into shots so the app can show "one capture" rather than a
        # flat wall of band thumbnails.
        shots: Dict[str, Dict] = {}
        for frame in frames:
            shot = shots.setdefault(
                frame.shot_id,
                {
                    "shot_id": frame.shot_id,
                    "session_id": frame.session_id,
                    "captured_at": frame.created_at.isoformat() if frame.created_at else None,
                    "lat": frame.lat,
                    "lon": frame.lon,
                    "alt_m": frame.alt_m,
                    "bands": [],
                    "frames": [],
                },
            )
            shot["frames"].append(frame.to_dict(url_prefix=url_prefix))
            if frame.band:
                shot["bands"].append(frame.band)

        for shot in shots.values():
            shot["bands"] = sorted(set(shot["bands"]))
            shot["analysable"] = bool({"red", "nir"}.issubset(set(shot["bands"])))

        return {
            "status": "ok",
            "frames": [f.to_dict(url_prefix=url_prefix) for f in frames],
            "shots": list(shots.values()),
        }, 200
