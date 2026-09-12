"""Service layer for the MAVLink link: connect, upload, fly, monitor.

Static methods returning ``(response_dict, status_code)``, matching the other
services. This is the layer that joins the two halves of the app: a mission
planned from KML (or restored from history) becomes an actual mission written
to the vehicle, and the vehicle's telemetry comes back in the shape the
Flutter live-mission screen expects.

Everything degrades politely: with no pymavlink installed, or no vehicle on
the wire, the endpoints answer with a readable message instead of a stack
trace, and the app keeps its simulated flight.

Two rules here exist because of what a *real* aircraft does with these calls:

* **A stop is a stop.** Return Home, Land and Hold shut the spray valve first
  (a change of flight mode does not) and cancel a launch that is still
  running, so the launch's last step cannot put the aircraft back into AUTO a
  moment after the operator told it to come home.
* **Don't cut the cord mid-flight.** Closing or moving the link while the
  aircraft is armed takes away its telemetry and the app's Return Home and
  Land buttons, so it is refused unless the caller insists.
"""

import os
from typing import List, Optional

from app.mavlink import MavlinkError, link, normalise_waypoints, summarise
from app.mavlink.link import DEFAULT_URL, force_allowed
from app.mavlink.mission_items import build_mission_items
from app.repositories.mission_repository import MissionRepository

# Flight modes the app is allowed to ask for, mapped to the link's helpers.
_ACTIONS = ("arm", "disarm", "takeoff", "rtl", "land", "hold", "auto", "guided")

# Actions whose whole point is to stop what the aircraft is doing.
_STOP_ACTIONS = ("rtl", "land", "hold", "disarm")

# Hosts that give a process no way to reach a drone: no serial port for a
# telemetry radio, and no inbound UDP for a field network to stream into.
_CLOUD_MARKERS = (
    "RAILWAY_ENVIRONMENT", "RAILWAY_PROJECT_ID", "RAILWAY_SERVICE_ID",
    "DYNO", "K_SERVICE", "WEBSITE_INSTANCE_ID",
)
# …with one exception: dialling *out* to a public address still works.
_OUTBOUND_SCHEMES = ("tcp:", "udpout:", "udpbcast:")


def _fail(message, status=400):
    return {"status": "error", "message": message}, status


def _in_the_cloud() -> bool:
    if os.environ.get("MAVLINK_ALLOW_CLOUD", "").strip().lower() in ("1", "true", "yes"):
        return False
    return any(os.environ.get(name) for name in _CLOUD_MARKERS)


def _cloud_refusal(url: str) -> Optional[str]:
    """Why this server cannot reach a drone — when it is one that cannot.

    Without this the operator waits out the 15-second heartbeat timeout and
    gets "no heartbeat", which reads like a problem with the aircraft. The
    problem is that the backend is in a data centre and the drone is in a
    field.
    """
    if not _in_the_cloud():
        return None
    if url.lower().startswith(_OUTBOUND_SCHEMES):
        return None
    return (
        f"This server runs in the cloud, so it cannot open {url}: it has no "
        "telemetry radio, and nothing on the field's own network can send to "
        "it. Run the backend on the ground-station laptop at the field, plug "
        "the telemetry radio into that laptop, and point the app at its "
        "address (for example http://192.168.1.5:5000). Everything else in "
        "the app keeps working against this server."
    )


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
        effective_url = (url or DEFAULT_URL).strip()

        refusal = _cloud_refusal(effective_url)
        if refusal:
            return _fail(refusal, 409)

        try:
            baud = int(payload.get("baud") or 57600)
            timeout = float(payload.get("timeout_s") or 15.0)
        except (TypeError, ValueError):
            return _fail("baud and timeout_s must be numbers.")

        # Moving the link while the aircraft is armed cuts telemetry and the
        # Return Home / Land buttons to something that is still flying.
        current = link.snapshot()
        if (
            current["connected"]
            and current["alive"]
            and current["telemetry"].get("armed")
            and current["url"] != effective_url
            and not bool(payload.get("force"))
        ):
            return _fail(
                f"The drone is armed on {current['url']}. Connecting somewhere "
                "else would cut the telemetry and the Return Home / Land "
                "buttons to an aircraft that is still flying. Land it first, "
                "or send force=true.",
                409,
            )

        try:
            snapshot = link.connect(url=url, baud=baud, timeout=timeout)
        except MavlinkError as exc:
            return _fail(str(exc), exc.status)
        except Exception as exc:  # unexpected
            return _fail(f"MAVLink connect failed: {exc}", 500)

        return {
            "status": "ok",
            "message": f"Connected to vehicle on {snapshot['url']}.",
            **snapshot,
        }, 200

    @staticmethod
    def disconnect(payload=None):
        payload = payload if isinstance(payload, dict) else {}
        current = link.snapshot()
        if (
            current["connected"]
            and current["alive"]
            and current["telemetry"].get("armed")
            and not bool(payload.get("force"))
        ):
            return _fail(
                "The drone is armed. Closing the link stops the telemetry and "
                "the app's Return Home / Land buttons, and the autopilot may "
                "fall back to its own ground-station failsafe. Land and "
                "disarm first, or send force=true.",
                409,
            )

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
            return _fail(str(exc), exc.status)
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
    def preflight():
        """What would stop a launch right now — for the app's pre-flight card.

        Read-only: the same checks :meth:`start_mission` runs, so the operator
        sees them before committing rather than as a refusal afterwards.
        """
        if not link.is_available():
            return {
                "status": "ok",
                "ready": False,
                "problems": ["pymavlink is not installed on the server."],
                **link.snapshot(),
            }, 200

        snapshot = link.snapshot()
        problems: List[str] = []
        if not snapshot["connected"]:
            problems.append("No vehicle connected.")
        elif not snapshot["flight_control_supported"]:
            problems.append(
                "This vehicle's autopilot is not one the app flies "
                "(ArduPilot only)."
            )
        else:
            problems.extend(link.preflight_problems())

        return {
            "status": "ok",
            "ready": not problems,
            "problems": problems,
            **snapshot,
        }, 200

    @staticmethod
    def start_mission(payload):
        """Pre-flight checks, arm, AUTO, MISSION_START, mission in progress."""
        if not link.is_available():
            return _fail("pymavlink is not installed on the server.", 503)

        payload = payload if isinstance(payload, dict) else {}
        try:
            result = link.start_mission()
        except MavlinkError as exc:
            return _fail(str(exc), exc.status)
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

        force = bool(payload.get("force"))
        if force and not force_allowed():
            return _fail(
                "Force arming and disarming skip the autopilot's safety checks "
                "(and force-disarm stops the motors in mid-air), so they are "
                "switched off. Set MAVLINK_ALLOW_FORCE_ARM=1 on the server for "
                "bench testing.",
                403,
            )

        warnings: List[str] = []
        if action in _STOP_ACTIONS:
            # Cancel a launch that is still running: its last step would put
            # the aircraft back into AUTO moments after this.
            link.interrupt()
            warnings = MavlinkService._close_spray_valve()

        try:
            if action == "arm":
                result = link.arm(force=force)
            elif action == "disarm":
                result = link.disarm(force=force)
            elif action == "takeoff":
                altitude = payload.get("altitude_m", 10.0)
                try:
                    altitude = float(altitude)
                except (TypeError, ValueError):
                    return _fail("altitude_m must be a number.")
                if altitude <= 0:
                    return _fail("altitude_m must be greater than 0.")
                problems = link.preflight_problems()
                if problems:
                    return _fail("Not taking off. " + " ".join(problems), 409)
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
            return _fail(str(exc), exc.status)
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
            "warnings": warnings,
            **link.snapshot(),
        }, 200

    # ── helpers ───────────────────────────────────────────────────────────

    @staticmethod
    def _close_spray_valve() -> List[str]:
        """Shut the pump before the aircraft is sent somewhere else.

        Only when what is loaded is a spray run: on a survey aircraft the same
        command would drive whatever else happens to be wired to that servo or
        relay. Best effort — a valve that will not answer must not stop a
        Return Home.
        """
        if link.mission_kind != "spray":
            return []
        try:
            from app.services.spray_service import SprayService

            _steps, errors = SprayService.close_valve(timeout=1.5)
            return errors
        except Exception as exc:  # pragma: no cover - defensive
            return [f"Could not close the spray valve: {exc}"]

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
