"""Service layer for the MAVLink link: connect, upload, fly, monitor.

Static methods returning ``(response_dict, status_code)``, matching the other
services. This is the layer that joins the two halves of the app: a mission
planned from KML (or restored from history) becomes an actual mission written
to the vehicle, and the vehicle's telemetry comes back in the shape the
Flutter live-mission screen expects.

Everything degrades politely: with no pymavlink installed, or no vehicle on
the wire, the endpoints answer with a readable message instead of a stack
trace, and the app keeps its simulated flight.
"""

import os

from app.mavlink import MavlinkError, link, normalise_waypoints, summarise
from app.mavlink.mission_items import build_mission_items
from app.repositories.mission_repository import MissionRepository

# Flight modes the app is allowed to ask for, mapped to the link's helpers.
_ACTIONS = ("arm", "disarm", "takeoff", "rtl", "land", "hold", "auto", "guided")


def _fail(message, status=400):
    return {"status": "error", "message": message}, status


class MavlinkService:

    # ── link lifecycle ────────────────────────────────────────────────────

    @staticmethod
    def status():
        """Link state + latest telemetry. Never fails — the app polls this."""
        return {"status": "ok", **link.snapshot()}, 200

    @staticmethod
    def connect(payload):
        if not link.is_available():
            return _fail(
                "pymavlink is not installed on the server. "
                "Run: pip install pymavlink",
                503,
            )

        payload = payload if isinstance(payload, dict) else {}
        url = payload.get("url") or os.environ.get("MAVLINK_URL")

        try:
            baud = int(payload.get("baud") or 57600)
            timeout = float(payload.get("timeout_s") or 15.0)
        except (TypeError, ValueError):
            return _fail("baud and timeout_s must be numbers.")

        try:
            snapshot = link.connect(url=url, baud=baud, timeout=timeout)
        except MavlinkError as exc:
            return _fail(str(exc), 502)
        except Exception as exc:  # unexpected
            return _fail(f"MAVLink connect failed: {exc}", 500)

        return {
            "status": "ok",
            "message": f"Connected to vehicle on {snapshot['url']}.",
            **snapshot,
        }, 200

    @staticmethod
    def disconnect():
        snapshot = link.disconnect()
        return {"status": "ok", "message": "MAVLink link closed.", **snapshot}, 200

    # ── mission upload ────────────────────────────────────────────────────

    @staticmethod
    def upload_mission(payload, user_id=None):
        """Write a mission to the vehicle.

        Accepts either an inline plan::

            {"waypoints": [{"lat":..,"lon":..}], "altitude_m": 30, "speed_ms": 7}

        or a mission already saved by the planner::

            {"mission_id": 12}

        ``dry_run: true`` builds the item list and returns it without touching
        the vehicle — handy for checking a plan with no drone connected.
        """
        payload = payload if isinstance(payload, dict) else {}

        waypoints = payload.get("waypoints")
        altitude_m = payload.get("altitude_m")
        speed_ms = payload.get("speed_ms")
        mission_name = payload.get("name")

        # Pull the plan from mission history when only an id was given.
        mission_id = payload.get("mission_id")
        if mission_id is not None and not waypoints:
            mission = MissionRepository.get_by_id(mission_id)
            if mission is None:
                return _fail("Mission not found.", 404)
            if mission.user_id is not None and user_id is not None \
                    and mission.user_id != user_id:
                return _fail("Not your mission.", 403)

            waypoints = mission.waypoints_list()
            altitude_m = altitude_m if altitude_m is not None else mission.altitude_m
            speed_ms = speed_ms if speed_ms is not None else mission.speed_ms
            mission_name = mission_name or mission.name

        try:
            altitude_m = float(altitude_m if altitude_m is not None else 30.0)
            speed_ms = float(speed_ms) if speed_ms is not None else None
        except (TypeError, ValueError):
            return _fail("altitude_m and speed_ms must be numbers.")

        cleaned = normalise_waypoints(waypoints, default_alt_m=altitude_m)
        if not cleaned:
            return _fail(
                "No usable waypoints. Send 'waypoints': [{'lat':..,'lon':..}] "
                "or a 'mission_id' from mission history."
            )

        return_home = payload.get("return_to_launch")
        return_home = True if return_home is None else bool(return_home)

        # Preview mode: no vehicle needed.
        if bool(payload.get("dry_run")):
            try:
                items = build_mission_items(
                    cleaned,
                    altitude_m=altitude_m,
                    speed_ms=speed_ms,
                    return_to_launch=return_home,
                )
            except ValueError as exc:
                return _fail(str(exc))
            return {
                "status": "ok",
                "message": f"Mission plan is valid ({len(items)} items).",
                "dry_run": True,
                "name": mission_name,
                "summary": summarise(items),
                "items": items,
            }, 200

        if not link.is_available():
            return _fail(
                "pymavlink is not installed on the server. "
                "Run: pip install pymavlink",
                503,
            )

        try:
            result = link.upload_mission(
                cleaned,
                altitude_m=altitude_m,
                speed_ms=speed_ms,
                return_to_launch=return_home,
            )
        except MavlinkError as exc:
            return _fail(str(exc), 502)
        except ValueError as exc:
            return _fail(str(exc))
        except Exception as exc:  # unexpected
            return _fail(f"Mission upload failed: {exc}", 500)

        # Remember what is loaded in the vehicle right now, so a reconnecting
        # app can tell whether the drone is flying the plan on screen.
        if mission_id is not None:
            MavlinkService._remember_uploaded(mission_id)

        return {
            "status": "ok",
            "message": f"Uploaded {result['uploaded']} mission items to the vehicle.",
            "name": mission_name,
            "mission_id": mission_id,
            "summary": summarise(result["items"]),
            "uploaded": result["uploaded"],
            **link.snapshot(),
        }, 200

    _uploaded_mission_id = None

    @staticmethod
    def _remember_uploaded(mission_id):
        try:
            MavlinkService._uploaded_mission_id = int(mission_id)
        except (TypeError, ValueError):
            MavlinkService._uploaded_mission_id = None

    # ── flight control ────────────────────────────────────────────────────

    @staticmethod
    def start_mission(payload):
        """AUTO + arm + MISSION_START, then mark the mission in progress."""
        if not link.is_available():
            return _fail("pymavlink is not installed on the server.", 503)

        payload = payload if isinstance(payload, dict) else {}
        try:
            result = link.start_mission()
        except MavlinkError as exc:
            return _fail(str(exc), 502)
        except Exception as exc:
            return _fail(f"Could not start the mission: {exc}", 500)

        mission_id = payload.get("mission_id") or MavlinkService._uploaded_mission_id
        if mission_id is not None:
            MavlinkService._set_mission_status(mission_id, "in_progress")

        return {
            "status": "ok",
            "message": "Mission started — vehicle is flying the plan.",
            "detail": result,
            **link.snapshot(),
        }, 200

    @staticmethod
    def command(payload):
        """Single flight action: arm / disarm / takeoff / rtl / land / hold."""
        if not link.is_available():
            return _fail("pymavlink is not installed on the server.", 503)

        payload = payload if isinstance(payload, dict) else {}
        action = str(payload.get("action") or "").lower().strip()
        if action not in _ACTIONS:
            return _fail(f"'action' must be one of: {', '.join(_ACTIONS)}.")

        try:
            if action == "arm":
                result = link.arm(force=bool(payload.get("force")))
            elif action == "disarm":
                result = link.disarm(force=bool(payload.get("force")))
            elif action == "takeoff":
                altitude = payload.get("altitude_m", 10.0)
                try:
                    altitude = float(altitude)
                except (TypeError, ValueError):
                    return _fail("altitude_m must be a number.")
                if altitude <= 0:
                    return _fail("altitude_m must be greater than 0.")
                # Copter only accepts a takeoff from GUIDED.
                link.set_mode("GUIDED")
                if not link.snapshot()["telemetry"].get("armed"):
                    link.arm()
                result = link.takeoff(altitude)
            elif action == "rtl":
                result = link.return_to_launch()
            elif action == "land":
                result = link.land()
            elif action == "hold":
                result = link.hold()
            else:  # auto | guided
                result = link.set_mode(action.upper())
        except MavlinkError as exc:
            return _fail(str(exc), 502)
        except Exception as exc:
            return _fail(f"Command '{action}' failed: {exc}", 500)

        # RTL/land end the flight: close the history entry too.
        if action in ("rtl", "land"):
            mission_id = payload.get("mission_id") \
                or MavlinkService._uploaded_mission_id
            if mission_id is not None:
                MavlinkService._set_mission_status(mission_id, "partial")

        return {
            "status": "ok",
            "message": f"Vehicle accepted '{action}'.",
            "detail": result,
            **link.snapshot(),
        }, 200

    # ── helpers ───────────────────────────────────────────────────────────

    @staticmethod
    def _set_mission_status(mission_id, status_value):
        """Best-effort history update — a DB hiccup must not fail a flight."""
        try:
            mission = MissionRepository.get_by_id(int(mission_id))
            if mission is None:
                return
            mission.status = status_value
            MissionRepository.save()
        except Exception:
            pass
