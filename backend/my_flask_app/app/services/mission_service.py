"""Service layer for drone-mission planning and mission history.

Static methods returning (response_dict, status_code), matching the other
services. Planning accepts KML either as an uploaded file's text or a raw
string and returns a ready-to-fly waypoint mission; saved missions are
persisted so the Home/Reports screens can list real history.
"""

import json
from datetime import datetime

from app.api.models.mission import Mission
from app.mission import build_mission, parse_kml
from app.repositories.mission_repository import MissionRepository

_MISSION_STATUSES = ("planned", "in_progress", "done", "partial", "aborted")


class MissionService:
    @staticmethod
    def plan_from_kml(
        kml_text: str,
        altitude_m: float = 60.0,
        line_spacing_m: float = 20.0,
    ) -> tuple:
        """Parse KML text and build a waypoint mission."""
        if not kml_text or not kml_text.strip():
            return {"status": "error", "message": "Empty KML content."}, 400

        # [DATA FLOW] KML text -> parse_kml (geometry) -> build_mission
        # (ordered lat/lon/alt waypoints). See docs/PREPROCESSING_DATAFLOW.md.
        try:
            parsed = parse_kml(kml_text)
            mission = build_mission(
                parsed,
                altitude_m=float(altitude_m),
                line_spacing_m=float(line_spacing_m),
            )
        except ValueError as exc:
            return {"status": "error", "message": str(exc)}, 400
        except Exception as exc:  # unexpected
            return {"status": "error", "message": f"Mission planning failed: {exc}"}, 500

        return {
            "status": "ok",
            "message": f"Mission planned with {mission['waypoint_count']} waypoints.",
            "geometry_counts": parsed["counts"],
            "mission": mission,
        }, 200

    # ── Mission history ────────────────────────────────────────────────────

    @staticmethod
    def save_mission(payload, user_id=None):
        """Persist a planned mission (name + settings + waypoint list)."""
        if not isinstance(payload, dict):
            return {"status": "error", "message": "Request body must be JSON."}, 400

        name = str(payload.get("name") or "").strip()
        if not name:
            return {"status": "error", "message": "Mission 'name' is required."}, 400

        waypoints = payload.get("waypoints") or []
        if not isinstance(waypoints, list):
            return {"status": "error", "message": "'waypoints' must be a list."}, 400

        def _num(key):
            value = payload.get(key)
            if value is None:
                return None
            try:
                return float(value)
            except (TypeError, ValueError):
                return None

        mission = Mission(
            user_id=user_id,
            name=name,
            mode=payload.get("mode"),
            area_ha=_num("area_ha"),
            altitude_m=_num("altitude_m"),
            speed_ms=_num("speed_ms"),
            overlap_pct=int(_num("overlap_pct") or 0) or None,
            line_spacing_m=_num("line_spacing_m"),
            status="planned",
            waypoint_count=len(waypoints),
            waypoints=json.dumps(waypoints),
        )
        MissionRepository.create(mission)

        return {
            "status": "ok",
            "message": f"Mission '{name}' saved.",
            "mission": mission.to_dict(),
        }, 201

    @staticmethod
    def list_missions(user_id=None):
        missions = MissionRepository.list_missions(user_id=user_id)
        return {
            "status": "ok",
            "missions": [m.to_dict() for m in missions],
        }, 200

    @staticmethod
    def update_status(mission_id, payload, user_id=None):
        mission = MissionRepository.get_by_id(mission_id)
        if mission is None:
            return {"status": "error", "message": "Mission not found."}, 404
        if mission.user_id is not None and mission.user_id != user_id:
            return {"status": "error", "message": "Not your mission."}, 403

        status_value = str((payload or {}).get("status") or "").lower()
        if status_value not in _MISSION_STATUSES:
            return {
                "status": "error",
                "message": f"'status' must be one of: {', '.join(_MISSION_STATUSES)}.",
            }, 400

        mission.status = status_value
        if status_value in ("done", "partial", "aborted"):
            mission.completed_at = datetime.utcnow()
            duration = (payload or {}).get("duration_min")
            if duration is not None:
                try:
                    mission.duration_min = float(duration)
                except (TypeError, ValueError):
                    pass
        MissionRepository.save()

        return {"status": "ok", "mission": mission.to_dict()}, 200
