"""Service layer for drone-mission planning from KML uploads.

Static methods returning (response_dict, status_code), matching the other
services. Accepts KML either as an uploaded file's text or a raw string, parses
it, and returns a ready-to-fly waypoint mission.
"""

from app.mission import build_mission, parse_kml


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
