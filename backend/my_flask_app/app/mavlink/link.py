"""Live MAVLink link to a flight controller — real hardware or a SITL sim.

One process-wide :class:`MavlinkLink` (see :data:`link`) owns the connection.
A single background thread does *all* the receiving: it keeps a telemetry
snapshot up to date, sends the GCS heartbeat the autopilot expects, and hands
messages to whoever is waiting for them. Request threads never touch the
socket's read side, so a telemetry poll can't steal a command's ACK.

Connection strings are pymavlink's (``MAVLINK_URL`` in .env sets the default):

    udpin:0.0.0.0:14550    listen for a GCS stream (Mission Planner SITL,
                           MAVProxy ``--out``) — the usual simulator setup
    udpout:10.0.0.5:14550  push to a fixed endpoint
    tcp:127.0.0.1:5760     connect straight to ArduPilot SITL
    COM5 / /dev/ttyACM0    a real radio or USB link (pass ``baud``)

pymavlink is an optional dependency: if it isn't installed the rest of the
backend still starts, and the /api/mavlink endpoints answer 503 with a clear
message instead of blowing up at import time.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from typing import Callable, Dict, List, Optional

from app.mavlink.mission_items import MISSION_TYPE_MISSION, build_mission_items

logger = logging.getLogger(__name__)

try:  # optional dependency — see module docstring
    from pymavlink import mavutil
except Exception:  # pragma: no cover - depends on the environment
    mavutil = None


DEFAULT_URL = "udpin:0.0.0.0:14550"

# Our identity on the MAVLink network. 255/190 is the conventional ground
# station address — but it is also exactly what Mission Planner and QGC use,
# and two GCSes sharing an address on one link is a real problem: the vehicle
# addresses its MISSION_REQUEST / COMMAND_ACK replies to the requesting
# sysid/compid, so the other station sees them too and can answer first,
# corrupting an upload. Set MAVLINK_SOURCE_SYSTEM=254 when another GCS is
# watching the same vehicle.
DEFAULT_SOURCE_SYSTEM = 255
DEFAULT_SOURCE_COMPONENT = 190

# A vehicle is considered "live" while heartbeats keep arriving.
HEARTBEAT_TIMEOUT_S = 5.0


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        logger.warning("%s is not a number; using %s", name, default)
        return default


def _connection_hint(url: str, exc: Exception) -> str:
    """Turn a raw socket error into something the operator can act on.

    "[WinError 10061] No connection could be made because the target machine
    actively refused it" is accurate and useless. What it almost always means
    here is that someone picked a `tcp:` address for a simulator that is on a
    different machine — the two directions are easy to mix up, so say so.
    """
    text = str(exc)
    errno = getattr(exc, "errno", None)

    # Connection refused: nothing is accepting on that TCP port.
    if errno in (61, 111, 10061) or "10061" in text or "refused" in text.lower():
        hint = f"Nothing is listening at {url}."
        if url.startswith(("tcp:", "tcpin:")):
            hint += (
                " A 'tcp:' address means the backend dials out to a simulator "
                "on that exact host — it only works when the simulator runs on "
                "this machine. For a simulator on another laptop, use "
                f"'{DEFAULT_URL}' instead and add a UDP output on the simulator "
                "pointing back here."
            )
        return hint

    # Port already taken: another GCS, or our own listener from a previous run.
    # Windows reports a UDP rebind as WSAEACCES (10013), not WSAEADDRINUSE —
    # the wording covers both readings because 10013 can also be a genuine
    # permission problem on a privileged port.
    if (
        errno in (13, 48, 98, 10013, 10048)
        or "10048" in text
        or "10013" in text
        or "in use" in text.lower()
    ):
        return (
            f"Could not bind {url} — the port is already in use, or blocked by "
            "permissions. Something else usually holds it: the diagnostic tool "
            "(tools/mavlink_listen.py), another ground station, or an earlier "
            "link that was not closed. Stop it and try again."
        )

    # Bad hostname.
    if "getaddrinfo" in text or "11001" in text or "name or service" in text.lower():
        return f"Could not resolve the address in '{url}'. Check the hostname or IP."

    return f"Could not open {url}: {exc}"

_MAV_RESULT = {
    0: "accepted",
    1: "temporarily_rejected",
    2: "denied",
    3: "unsupported",
    4: "failed",
    5: "in_progress",
    6: "cancelled",
}


class MavlinkError(RuntimeError):
    """Anything the caller should see as a readable failure message."""


class _Waiter:
    """A request thread parked on the next message matching a predicate."""

    def __init__(self, types, predicate: Optional[Callable] = None):
        self.types = set(types)
        self.predicate = predicate
        self.event = threading.Event()
        self.message = None


class MavlinkLink:
    """Owns the MAVLink connection, its reader thread and telemetry cache."""

    def __init__(self):
        self._master = None
        self._url: Optional[str] = None
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()

        self._send_lock = threading.Lock()   # serialises writes to the socket
        self._state_lock = threading.RLock()  # guards the fields below

        self._waiters: List[_Waiter] = []
        self._telemetry: Dict = self._blank_telemetry()
        self._statustexts: List[Dict] = []
        self._last_heartbeat: float = 0.0
        self._connected_at: float = 0.0
        self._target_system = 1
        self._target_component = 1

    # ── availability ──────────────────────────────────────────────────────

    @staticmethod
    def is_available() -> bool:
        """False when pymavlink isn't installed (endpoints then answer 503)."""
        return mavutil is not None

    @property
    def is_connected(self) -> bool:
        with self._state_lock:
            return self._master is not None

    @property
    def is_alive(self) -> bool:
        """Connected *and* still hearing heartbeats from the vehicle."""
        with self._state_lock:
            if self._master is None:
                return False
            return (time.time() - self._last_heartbeat) < HEARTBEAT_TIMEOUT_S

    # ── connect / disconnect ──────────────────────────────────────────────

    def connect(
        self,
        url: Optional[str] = None,
        baud: int = 57600,
        timeout: float = 15.0,
    ) -> Dict:
        """Open the link and block until the first heartbeat arrives.

        Reconnecting to the same URL while already connected is a no-op.
        """
        if mavutil is None:
            raise MavlinkError(
                "pymavlink is not installed on the server. "
                "Run: pip install pymavlink"
            )

        url = (url or os.environ.get("MAVLINK_URL") or DEFAULT_URL).strip()

        with self._state_lock:
            if self._master is not None and self._url == url:
                return self.snapshot()

        # A different endpoint was requested — drop the old one first.
        self.disconnect()

        source_system = _env_int("MAVLINK_SOURCE_SYSTEM", DEFAULT_SOURCE_SYSTEM)
        source_component = _env_int(
            "MAVLINK_SOURCE_COMPONENT", DEFAULT_SOURCE_COMPONENT
        )

        logger.info(
            "MAVLink: connecting to %s as GCS %s/%s",
            url, source_system, source_component,
        )
        try:
            master = mavutil.mavlink_connection(
                url,
                baud=baud,
                # Ground-station identity; see DEFAULT_SOURCE_SYSTEM above for
                # why this is configurable.
                source_system=source_system,
                source_component=source_component,
                autoreconnect=True,
                # pymavlink's TCP path otherwise retries three times, printing
                # the raw socket error and sleeping a second between each. A
                # refused connection is not going to succeed on retry, and the
                # delay just makes the app look hung — fail immediately and
                # report something the operator can act on.
                retries=0,
            )
        except Exception as exc:
            raise MavlinkError(_connection_hint(url, exc)) from exc

        try:
            heartbeat = master.wait_heartbeat(timeout=timeout)
        except Exception as exc:
            master.close()
            raise MavlinkError(f"Link error on {url}: {exc}") from exc

        if heartbeat is None:
            master.close()
            raise MavlinkError(
                f"No heartbeat on {url} within {timeout:.0f}s. "
                "Is the simulator or vehicle streaming to this address?"
            )

        with self._state_lock:
            self._master = master
            self._url = url
            self._target_system = master.target_system
            self._target_component = master.target_component or 1
            self._last_heartbeat = time.time()
            self._connected_at = time.time()
            self._telemetry = self._blank_telemetry()
            self._statustexts = []

        self._stop.clear()
        self._thread = threading.Thread(
            target=self._reader_loop, name="mavlink-reader", daemon=True
        )
        self._thread.start()

        self._request_streams()
        logger.info(
            "MAVLink: connected to %s (system %s)", url, master.target_system
        )
        return self.snapshot()

    def disconnect(self) -> Dict:
        """Close the link and stop the reader thread. Safe to call any time."""
        self._stop.set()
        thread = self._thread
        if thread is not None and thread.is_alive() and \
                thread is not threading.current_thread():
            thread.join(timeout=2.0)
        self._thread = None

        with self._state_lock:
            master, self._master = self._master, None
            self._url = None
            self._last_heartbeat = 0.0
            self._connected_at = 0.0
            self._telemetry = self._blank_telemetry()
            # Release anyone still parked on a message.
            for waiter in self._waiters:
                waiter.event.set()
            self._waiters = []

        if master is not None:
            try:
                master.close()
            except Exception:
                pass
            logger.info("MAVLink: disconnected")

        return self.snapshot()

    # ── reader thread ─────────────────────────────────────────────────────

    def _reader_loop(self):
        """Only thread that reads the socket; also emits our GCS heartbeat."""
        last_beat = 0.0
        while not self._stop.is_set():
            master = self._master
            if master is None:
                break

            # 1 Hz GCS heartbeat keeps the autopilot's link failsafe happy.
            now = time.time()
            if now - last_beat >= 1.0:
                last_beat = now
                self._send_heartbeat()

            try:
                msg = master.recv_match(blocking=True, timeout=0.5)
            except Exception as exc:
                if not self._stop.is_set():
                    logger.warning("MAVLink: receive error: %s", exc)
                time.sleep(0.2)
                continue

            if msg is None:
                continue
            msg_type = msg.get_type()
            if msg_type in ("BAD_DATA", None):
                continue

            try:
                self._absorb(msg, msg_type)
            except Exception as exc:  # never let one bad message kill the loop
                logger.debug("MAVLink: could not absorb %s: %s", msg_type, exc)

            self._dispatch(msg, msg_type)

    def _send_heartbeat(self):
        master = self._master
        if master is None or mavutil is None:
            return
        try:
            with self._send_lock:
                master.mav.heartbeat_send(
                    mavutil.mavlink.MAV_TYPE_GCS,
                    mavutil.mavlink.MAV_AUTOPILOT_INVALID,
                    0, 0, 0,
                )
        except Exception:
            pass

    def _dispatch(self, msg, msg_type: str):
        """Hand the message to any request thread waiting for it."""
        with self._state_lock:
            if not self._waiters:
                return
            still_waiting = []
            for waiter in self._waiters:
                matched = msg_type in waiter.types and (
                    waiter.predicate is None or waiter.predicate(msg)
                )
                if matched:
                    waiter.message = msg
                    waiter.event.set()
                else:
                    still_waiting.append(waiter)
            self._waiters = still_waiting

    def _register(self, types, predicate=None) -> _Waiter:
        """Start listening for a reply *before* sending the request.

        Registering after the send loses the race on a local link: SITL can
        answer in well under a millisecond, and an ACK that arrives before the
        waiter exists is dropped, stalling the caller for its whole timeout.
        """
        waiter = _Waiter(types, predicate)
        with self._state_lock:
            if self._master is None:
                raise MavlinkError("Not connected to a vehicle.")
            self._waiters.append(waiter)
        return waiter

    def _wait(self, waiter: _Waiter, timeout: float):
        """Block on a registered waiter; None when nothing matched in time."""
        if not waiter.event.wait(timeout):
            with self._state_lock:
                if waiter in self._waiters:
                    self._waiters.remove(waiter)
            return None
        return waiter.message

    def _expect(self, types, timeout: float = 5.0, predicate=None):
        """Register and wait in one step — only for unsolicited messages
        (heartbeats), never for a reply to something we are about to send."""
        return self._wait(self._register(types, predicate), timeout)

    # ── telemetry ─────────────────────────────────────────────────────────

    @staticmethod
    def _blank_telemetry() -> Dict:
        return {
            "armed": False,
            "mode": None,
            "system_status": None,
            "lat": None,
            "lon": None,
            "relative_alt_m": None,
            "alt_msl_m": None,
            "heading_deg": None,
            "groundspeed_ms": None,
            "airspeed_ms": None,
            "climb_ms": None,
            "throttle_pct": None,
            "battery_percent": None,
            "voltage_v": None,
            "current_a": None,
            "gps_fix": None,
            "satellites": None,
            "current_wp": None,
            "mission_items": None,
        }

    def _absorb(self, msg, msg_type: str):
        """Fold one message into the telemetry snapshot."""
        with self._state_lock:
            telemetry = self._telemetry

            if msg_type == "HEARTBEAT":
                # Ignore heartbeats from other GCSes echoing on the same port.
                if msg.get_srcSystem() != self._target_system:
                    return
                self._last_heartbeat = time.time()
                telemetry["armed"] = bool(
                    msg.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED
                )
                telemetry["mode"] = self._mode_name(msg)
                telemetry["system_status"] = self._enum_name(
                    "MAV_STATE", msg.system_status, "MAV_STATE_"
                )

            elif msg_type == "GLOBAL_POSITION_INT":
                telemetry["lat"] = msg.lat / 1e7
                telemetry["lon"] = msg.lon / 1e7
                telemetry["alt_msl_m"] = msg.alt / 1000.0
                telemetry["relative_alt_m"] = msg.relative_alt / 1000.0
                telemetry["heading_deg"] = (
                    msg.hdg / 100.0 if msg.hdg != 65535 else None
                )

            elif msg_type == "VFR_HUD":
                telemetry["groundspeed_ms"] = float(msg.groundspeed)
                telemetry["airspeed_ms"] = float(msg.airspeed)
                telemetry["climb_ms"] = float(msg.climb)
                telemetry["throttle_pct"] = int(msg.throttle)
                if telemetry["heading_deg"] is None:
                    telemetry["heading_deg"] = float(msg.heading)

            elif msg_type == "SYS_STATUS":
                telemetry["voltage_v"] = (
                    msg.voltage_battery / 1000.0
                    if msg.voltage_battery not in (0, 65535) else None
                )
                telemetry["current_a"] = (
                    msg.current_battery / 100.0
                    if msg.current_battery != -1 else None
                )
                if msg.battery_remaining != -1:
                    telemetry["battery_percent"] = int(msg.battery_remaining)

            elif msg_type == "BATTERY_STATUS":
                if msg.battery_remaining != -1:
                    telemetry["battery_percent"] = int(msg.battery_remaining)

            elif msg_type == "GPS_RAW_INT":
                telemetry["gps_fix"] = int(msg.fix_type)
                telemetry["satellites"] = (
                    int(msg.satellites_visible)
                    if msg.satellites_visible != 255 else None
                )

            elif msg_type == "MISSION_CURRENT":
                telemetry["current_wp"] = int(msg.seq)

            elif msg_type == "STATUSTEXT":
                text = msg.text
                if isinstance(text, bytes):
                    text = text.decode("utf-8", errors="replace")
                self._statustexts.append({
                    "severity": int(msg.severity),
                    "text": text.strip("\x00").strip(),
                    "at": time.time(),
                })
                # Keep only the tail — this is a status strip, not a log file.
                del self._statustexts[:-30]

    @staticmethod
    def _enum_name(enum_name: str, value: int, prefix: str) -> Optional[str]:
        """Readable name for a MAVLink enum value ('active', 'standby', ...)."""
        try:
            entry = mavutil.mavlink.enums[enum_name].get(value)
            if entry is not None:
                return entry.name.replace(prefix, "").lower()
        except Exception:
            pass
        return None

    def _mode_name(self, heartbeat) -> Optional[str]:
        try:
            mapping = self._master.mode_mapping() or {}
            for name, number in mapping.items():
                if number == heartbeat.custom_mode:
                    return name
        except Exception:
            pass
        return None

    def snapshot(self) -> Dict:
        """Link state + latest telemetry, as sent to the app."""
        with self._state_lock:
            connected = self._master is not None
            age = (
                time.time() - self._last_heartbeat
                if self._last_heartbeat else None
            )
            return {
                "available": mavutil is not None,
                "connected": connected,
                "alive": connected and age is not None
                and age < HEARTBEAT_TIMEOUT_S,
                "url": self._url,
                "target_system": self._target_system if connected else None,
                # Our own GCS address — worth surfacing when another ground
                # station shares the link and IDs need to differ.
                "source_system": _env_int(
                    "MAVLINK_SOURCE_SYSTEM", DEFAULT_SOURCE_SYSTEM
                ) if connected else None,
                "heartbeat_age_s": round(age, 2) if age is not None else None,
                "uptime_s": round(time.time() - self._connected_at, 1)
                if connected else None,
                "telemetry": dict(self._telemetry),
                "messages": list(self._statustexts[-8:]),
            }

    # ── commands ──────────────────────────────────────────────────────────

    def _require_link(self):
        if mavutil is None:
            raise MavlinkError(
                "pymavlink is not installed on the server. "
                "Run: pip install pymavlink"
            )
        if self._master is None:
            raise MavlinkError(
                "No vehicle connected. Connect the MAVLink link first."
            )
        return self._master

    def _request_streams(self):
        """Ask for a decent telemetry rate (older ArduPilot needs the nudge)."""
        master = self._master
        if master is None:
            return
        try:
            with self._send_lock:
                master.mav.request_data_stream_send(
                    self._target_system,
                    self._target_component,
                    mavutil.mavlink.MAV_DATA_STREAM_ALL,
                    4,  # Hz
                    1,  # start
                )
        except Exception as exc:
            logger.debug("MAVLink: stream request failed: %s", exc)

    def send_command_long(
        self,
        command: int,
        params=(0, 0, 0, 0, 0, 0, 0),
        timeout: float = 5.0,
        label: str = "command",
    ) -> Dict:
        """Send a COMMAND_LONG and wait for its COMMAND_ACK."""
        master = self._require_link()
        values = list(params) + [0.0] * (7 - len(params))

        waiter = self._register(
            ("COMMAND_ACK",), predicate=lambda m: m.command == command
        )
        with self._send_lock:
            master.mav.command_long_send(
                self._target_system,
                self._target_component,
                command,
                0,  # confirmation
                *[float(v) for v in values[:7]],
            )

        ack = self._wait(waiter, timeout)
        if ack is None:
            raise MavlinkError(f"No acknowledgement for {label} within {timeout:.0f}s.")

        result = _MAV_RESULT.get(ack.result, f"result_{ack.result}")
        if ack.result not in (0, 5):  # ACCEPTED / IN_PROGRESS
            raise MavlinkError(f"Vehicle rejected {label} ({result}).")
        return {"command": label, "result": result}

    def set_mode(self, mode: str, timeout: float = 5.0) -> Dict:
        """Switch flight mode by name (GUIDED, AUTO, RTL, LAND, LOITER…)."""
        master = self._require_link()
        mode = str(mode).upper().strip()

        mapping = master.mode_mapping() or {}
        if mode not in mapping:
            raise MavlinkError(
                f"Unknown flight mode '{mode}'. "
                f"Vehicle supports: {', '.join(sorted(mapping))}."
            )

        with self._state_lock:
            if self._telemetry.get("mode") == mode:
                return {"command": "set_mode", "mode": mode, "result": "already"}

        with self._send_lock:
            master.mav.set_mode_send(
                self._target_system,
                mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                mapping[mode],
            )

        # Confirm from the heartbeat rather than trusting the send.
        deadline = time.time() + timeout
        while time.time() < deadline:
            heartbeat = self._expect(("HEARTBEAT",), timeout=1.0)
            if heartbeat is None:
                continue
            with self._state_lock:
                if self._telemetry.get("mode") == mode:
                    return {"command": "set_mode", "mode": mode, "result": "accepted"}

        raise MavlinkError(f"Vehicle did not switch to {mode} within {timeout:.0f}s.")

    def arm(self, force: bool = False) -> Dict:
        self._require_link()
        # 21196 is the ArduPilot "force" magic number (skips pre-arm checks).
        return self.send_command_long(
            mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
            params=(1, 21196 if force else 0),
            label="arm",
            timeout=8.0,
        )

    def disarm(self, force: bool = False) -> Dict:
        self._require_link()
        return self.send_command_long(
            mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
            params=(0, 21196 if force else 0),
            label="disarm",
        )

    def takeoff(self, altitude_m: float) -> Dict:
        self._require_link()
        return self.send_command_long(
            mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
            params=(0, 0, 0, 0, 0, 0, float(altitude_m)),
            label="takeoff",
        )

    def return_to_launch(self) -> Dict:
        return self.set_mode("RTL")

    def land(self) -> Dict:
        return self.set_mode("LAND")

    def hold(self) -> Dict:
        """Pause the survey and hover (Copter LOITER / Plane-style HOLD)."""
        mapping = self._require_link().mode_mapping() or {}
        for name in ("LOITER", "HOLD", "BRAKE", "POSHOLD"):
            if name in mapping:
                return self.set_mode(name)
        raise MavlinkError("Vehicle has no loiter/hold mode.")

    # Modes to arm from, best first. GUIDED is what a ground station normally
    # uses; the others are fallbacks for frames that lack it.
    ARMABLE_MODES = ("GUIDED", "LOITER", "STABILIZE")

    def start_mission(self) -> Dict:
        """Arm, hand the aircraft to AUTO, and start the mission.

        The order is not the obvious one. ArduCopter **refuses to arm while in
        AUTO** — it answers "Arm: Auto mode not armable" — so setting AUTO
        first and then arming leaves the vehicle sitting on the ground with a
        perfectly good flight plan loaded and nothing happening. Arm from
        GUIDED, then switch to AUTO (which keeps the motors armed), then send
        MISSION_START: an armed copter in AUTO still will not move without it,
        because the throttle is down and nothing has told it to begin.
        """
        master = self._require_link()
        steps = []

        with self._state_lock:
            already_armed = self._telemetry.get("armed", False)

        if not already_armed:
            mapping = master.mode_mapping() or {}
            arming_mode = next(
                (mode for mode in self.ARMABLE_MODES if mode in mapping), None
            )
            if arming_mode is None:
                raise MavlinkError(
                    "Vehicle offers none of "
                    f"{', '.join(self.ARMABLE_MODES)} to arm from."
                )
            steps.append(self.set_mode(arming_mode))
            steps.append(self.arm())

        steps.append(self.set_mode("AUTO"))
        steps.append(
            self.send_command_long(
                mavutil.mavlink.MAV_CMD_MISSION_START,
                params=(0, 0),
                label="mission_start",
                timeout=8.0,
            )
        )
        return {"command": "start_mission", "steps": steps}

    # ── mission upload ────────────────────────────────────────────────────

    def upload_mission(
        self,
        waypoints: List[Dict],
        altitude_m: float = 30.0,
        speed_ms: Optional[float] = None,
        return_to_launch: bool = True,
        timeout: float = 30.0,
    ) -> Dict:
        """Write the waypoint list to the vehicle using the mission protocol.

        Sequence: clear the old mission → announce the new count → serve every
        MISSION_REQUEST the vehicle asks for → wait for MISSION_ACK.
        """
        master = self._require_link()

        with self._state_lock:
            home_lat = self._telemetry.get("lat")
            home_lon = self._telemetry.get("lon")

        items = build_mission_items(
            waypoints,
            altitude_m=altitude_m,
            home_lat=home_lat,
            home_lon=home_lon,
            speed_ms=speed_ms,
            return_to_launch=return_to_launch,
        )
        count = len(items)

        # Clear first so a shorter new mission can't leave stale tail items.
        waiter = self._register(("MISSION_ACK",))
        with self._send_lock:
            master.mav.mission_clear_all_send(
                self._target_system, self._target_component
            )
        self._wait(waiter, 3.0)

        # Every send below arms its waiter first — the vehicle answers a
        # mission message immediately, well before a post-send register.
        reply_types = ("MISSION_REQUEST", "MISSION_REQUEST_INT", "MISSION_ACK")
        waiter = self._register(reply_types)
        with self._send_lock:
            master.mav.mission_count_send(
                self._target_system,
                self._target_component,
                count,
                MISSION_TYPE_MISSION,
            )

        sent = set()
        deadline = time.time() + timeout
        while time.time() < deadline:
            msg = self._wait(
                waiter, min(5.0, max(0.5, deadline - time.time()))
            )
            if msg is None:
                raise MavlinkError(
                    f"Vehicle stopped requesting mission items "
                    f"({len(sent)}/{count} sent)."
                )

            if msg.get_type() == "MISSION_ACK":
                if msg.type == 0:  # MAV_MISSION_ACCEPTED
                    break
                raise MavlinkError(
                    f"Vehicle rejected the mission (error {msg.type})."
                )

            seq = int(msg.seq)
            waiter = self._register(reply_types)
            if not 0 <= seq < count:
                continue
            self._send_mission_item(items[seq])
            sent.add(seq)
        else:
            raise MavlinkError(
                f"Mission upload timed out ({len(sent)}/{count} items sent)."
            )

        # Point the vehicle at the first item so AUTO starts from the top.
        with self._send_lock:
            master.mav.mission_set_current_send(
                self._target_system, self._target_component, 0
            )

        with self._state_lock:
            self._telemetry["mission_items"] = count

        logger.info("MAVLink: uploaded %d mission items", count)
        return {"uploaded": count, "items": items}

    def _send_mission_item(self, item: Dict):
        master = self._master
        with self._send_lock:
            master.mav.mission_item_int_send(
                self._target_system,
                self._target_component,
                item["seq"],
                item["frame"],
                item["command"],
                item["current"],
                item["autocontinue"],
                item["param1"],
                item["param2"],
                item["param3"],
                item["param4"],
                int(round(item["lat"] * 1e7)),
                int(round(item["lon"] * 1e7)),
                float(item["alt"]),
                MISSION_TYPE_MISSION,
            )


# Process-wide link — the app flies one vehicle at a time.
link = MavlinkLink()
