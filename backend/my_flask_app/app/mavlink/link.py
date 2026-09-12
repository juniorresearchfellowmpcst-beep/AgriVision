"""Live MAVLink link to a flight controller — real hardware or a SITL sim.

One process-wide :class:`MavlinkLink` (see :data:`link`) owns the connection.
A single background thread does *all* the receiving: it keeps a telemetry
snapshot up to date, sends the GCS heartbeat the autopilot expects, and hands
messages to whoever is waiting for them. Request threads never touch the
socket's read side, so a telemetry poll can't steal a command's ACK.

Connection strings are pymavlink's (``MAVLINK_URL`` in .env sets the default):

    udpin:0.0.0.0:14550    listen for a stream sent here: SITL on another
                           machine, MAVProxy ``--out``, a Wi-Fi telemetry
                           bridge, a companion computer's mavlink-router
    udpout:10.0.0.5:14550  push to a fixed endpoint
    tcp:127.0.0.1:5760     connect straight to ArduPilot SITL
    COM5 / /dev/ttyUSB0    a telemetry radio or USB cable (pass ``baud``)

What a real aircraft needs that a simulator forgives, all handled here:

* **The right device.** A real link carries heartbeats from more than the
  flight controller: a MAVLink camera or gimbal, a companion computer, any
  other ground station watching the same aircraft. The link locks onto the
  first heartbeat that is actually an autopilot (:func:`is_vehicle_heartbeat`)
  and ignores everybody else's telemetry.
* **MAVLink 2** — see the note above the pymavlink import.
* **Reasons, not codes.** The autopilot explains a refused arm or mode change
  in a STATUSTEXT ("PreArm: GPS not healthy"); the error quotes it.
* **ArduPilot.** Missions, the launch sequence and the spray commands follow
  ArduPilot's conventions (home in seq 0, AUTO, DO_SPRAYER). Any other
  autopilot gets telemetry and a plain refusal for everything that moves it.

pymavlink is an optional dependency: if it isn't installed the rest of the
backend still starts, and the /api/mavlink endpoints answer 503 with a clear
message instead of blowing up at import time.
"""

from __future__ import annotations

import logging
import os
import queue
import threading
import time
from typing import Callable, Dict, List, Optional, Tuple

from app.mavlink.mission_items import MISSION_TYPE_MISSION, build_mission_items

logger = logging.getLogger(__name__)

# pymavlink picks its wire protocol when it is imported. Without MAVLINK20 it
# loads the MAVLink 1 parser and only switches if the very first byte it reads
# starts a MAVLink 2 frame. On a real telemetry radio that is luck: the radio's
# own injected status packets can arrive first, and a link stuck on the
# MAVLink 1 parser silently drops every MAVLink 2 frame ArduPilot sends — the
# connect then times out with "no heartbeat" beside a healthy aircraft. The
# MAVLink 2 parser reads both versions, so it is the safe default.
# MAVLINK_PROTOCOL=1 opts out, for a vehicle that only speaks MAVLink 1.
if os.environ.get("MAVLINK_PROTOCOL", "2").strip() != "1":
    os.environ.setdefault("MAVLINK20", "1")

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

# While no position/status telemetry arrives, ask for it again this often.
STREAM_RETRY_S = 5.0

# Below this charge a launch is refused (MAVLINK_MIN_LAUNCH_BATTERY overrides).
MIN_LAUNCH_BATTERY_PCT = 30

# Values from MAVLink's common enums, inlined so the vehicle checks work — and
# can be tested — without pymavlink.
AUTOPILOT_ARDUPILOT = 3   # MAV_AUTOPILOT_ARDUPILOTMEGA
AUTOPILOT_PX4 = 12        # MAV_AUTOPILOT_PX4
_AUTOPILOT_INVALID = 8    # MAV_AUTOPILOT_INVALID: "not a flight controller"
_COMP_ID_GIMBAL = 154     # MAV_COMP_ID_GIMBAL
# Heartbeat types that are never the aircraft: a ground station, a gimbal, an
# ADS-B receiver, a companion computer.
_NOT_A_VEHICLE = frozenset({6, 26, 27, 18})
# ArduPilot acknowledges a SET_MODE *message* with a COMMAND_ACK whose
# "command" is the message's own id.
_SET_MODE_ACK = 11

_AUTOPILOT_NAMES = {AUTOPILOT_ARDUPILOT: "ardupilot", AUTOPILOT_PX4: "px4"}


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        logger.warning("%s is not a number; using %s", name, default)
        return default


def _as_int(value) -> Optional[int]:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def force_allowed() -> bool:
    """Force-arm/disarm skips the autopilot's safety checks: bench use only."""
    return os.environ.get("MAVLINK_ALLOW_FORCE_ARM", "").strip().lower() in (
        "1", "true", "yes",
    )


def is_vehicle_heartbeat(msg) -> bool:
    """Is this HEARTBEAT from a flight controller, not a device beside it?

    Taking the first heartbeat to arrive — which is all pymavlink's
    ``wait_heartbeat()`` does — can lock the link onto a camera, a gimbal, a
    companion computer or another ground station, and every command then goes
    to a device that ignores it. This is the rule pymavlink itself uses to
    decide which system is the vehicle.
    """
    try:
        if msg.get_srcComponent() == _COMP_ID_GIMBAL:
            return False
        if int(msg.type) in _NOT_A_VEHICLE:
            return False
        return int(msg.autopilot) != _AUTOPILOT_INVALID
    except Exception:
        return False


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

    # A serial port that is not there, or is held by another program.
    if url.upper().startswith("COM") or url.startswith("/dev/"):
        return (
            f"Could not open the serial port {url}: {exc}. Check the radio or "
            "USB cable is plugged in, that this is its port (Device Manager on "
            "Windows, ls /dev/tty* on Linux), and that Mission Planner or "
            "QGroundControl is not already using it."
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

# MAV_MISSION_RESULT, worded to follow "the vehicle reported …".
_MISSION_RESULT = {
    1: "an error",
    2: "a coordinate frame it does not support",
    3: "a command it does not support",
    4: "more items than it has room for",
    5: "an invalid item",
    6: "an invalid item parameter",
    7: "an invalid item parameter",
    8: "an invalid item parameter",
    9: "an invalid item parameter",
    10: "an invalid latitude",
    11: "an invalid longitude",
    12: "an invalid altitude",
    13: "items sent out of order",
    14: "that the upload was denied",
    15: "that the upload was cancelled",
}

_GPS_FIX = {
    0: "no GPS",
    1: "no fix",
    2: "2-D fix only",
    3: "3-D fix",
    4: "DGPS",
    5: "RTK float",
    6: "RTK fixed",
}


class MavlinkError(RuntimeError):
    """Anything the caller should see as a readable failure message.

    ``status`` is the HTTP code the API answers with: 502 when the link or the
    vehicle failed, 409 when the request was refused because of the aircraft's
    state (armed, no GPS fix, an autopilot the app does not fly) — something
    the operator can fix rather than a fault.
    """

    def __init__(self, message: str, status: int = 502):
        super().__init__(message)
        self.status = status


class _Waiter:
    """A request thread parked on the next message matching a predicate."""

    def __init__(self, types, predicate: Optional[Callable] = None):
        self.types = set(types)
        self.predicate = predicate
        self.event = threading.Event()
        self.message = None


class _Subscription:
    """Every matching message, in order, until unsubscribed.

    For exchanges that span several messages. A mission upload is a stream of
    MISSION_REQUESTs and a final MISSION_ACK; a one-shot waiter re-armed after
    each message can miss one that arrives in between, a queue cannot.
    """

    def __init__(self, types, predicate: Optional[Callable] = None):
        self.types = set(types)
        self.predicate = predicate
        self.queue: "queue.Queue" = queue.Queue()

    def next(self, timeout: float):
        try:
            return self.queue.get(timeout=max(0.0, timeout))
        except queue.Empty:
            return None


def _matches(listener, msg, msg_type: str) -> bool:
    if msg_type not in listener.types:
        return False
    if listener.predicate is None:
        return True
    try:
        return bool(listener.predicate(msg))
    except Exception:  # a predicate must never take the reader thread down
        return False


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
        self._subscriptions: List[_Subscription] = []
        self._telemetry: Dict = self._blank_telemetry()
        self._statustexts: List[Dict] = []
        self._last_heartbeat: float = 0.0
        self._connected_at: float = 0.0
        self._target_system = 1
        self._target_component = 1
        self._source_system = DEFAULT_SOURCE_SYSTEM
        # What the vehicle says it is, from its heartbeat (None until then).
        self._autopilot: Optional[int] = None
        self._vehicle_type: Optional[int] = None
        # "survey" or "spray": what we last wrote to the vehicle, so a Return
        # Home knows whether there is a valve to close first.
        self._mission_kind: Optional[str] = None
        self._telemetry_at: float = 0.0
        self._stream_request_at: float = 0.0
        # Bumped by every stop-type command; see interrupt().
        self._interrupts = 0

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

    @property
    def mission_kind(self) -> Optional[str]:
        """What we last uploaded: "survey", "spray", or None."""
        with self._state_lock:
            return self._mission_kind if self._master is not None else None

    # ── connect / disconnect ──────────────────────────────────────────────

    def connect(
        self,
        url: Optional[str] = None,
        baud: int = 57600,
        timeout: float = 15.0,
    ) -> Dict:
        """Open the link and block until the vehicle's first heartbeat.

        Reconnecting to the same URL while already connected is a no-op.
        """
        if mavutil is None:
            raise MavlinkError(
                "pymavlink is not installed on the server. "
                "Run: pip install pymavlink",
                503,
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
            heartbeat, others = self._wait_for_vehicle(master, timeout)
        except Exception as exc:
            master.close()
            raise MavlinkError(f"Link error on {url}: {exc}") from exc

        if heartbeat is None:
            master.close()
            if others:
                raise MavlinkError(
                    f"No heartbeat from a flight controller on {url} within "
                    f"{timeout:.0f}s — only {others} from other devices (a "
                    "ground station, a camera or a companion computer). Check "
                    "that the autopilot itself is on this link."
                )
            raise MavlinkError(
                f"No heartbeat on {url} within {timeout:.0f}s. "
                "Is the simulator or vehicle streaming to this address?"
            )

        with self._state_lock:
            self._master = master
            self._url = url
            self._target_system = heartbeat.get_srcSystem()
            self._target_component = heartbeat.get_srcComponent() or 1
            self._source_system = source_system
            self._autopilot = _as_int(getattr(heartbeat, "autopilot", None))
            self._vehicle_type = _as_int(getattr(heartbeat, "type", None))
            self._mission_kind = None
            self._last_heartbeat = time.time()
            self._connected_at = time.time()
            self._telemetry = self._blank_telemetry()
            self._statustexts = []
            self._telemetry_at = 0.0

        # The heartbeat just waited for already says the mode and armed state;
        # fold it in so the very first status poll has them.
        try:
            self._absorb(heartbeat, "HEARTBEAT")
        except Exception:
            pass

        self._stop.clear()
        self._thread = threading.Thread(
            target=self._reader_loop, name="mavlink-reader", daemon=True
        )
        self._thread.start()

        self._request_streams()
        logger.info(
            "MAVLink: connected to %s (system %s, component %s, %s)",
            url, self._target_system, self._target_component,
            _AUTOPILOT_NAMES.get(self._autopilot, f"autopilot {self._autopilot}"),
        )
        return self.snapshot()

    @staticmethod
    def _wait_for_vehicle(master, timeout: float) -> Tuple[Optional[object], int]:
        """The first heartbeat from the aircraft itself, and how many others
        (from devices that are not the aircraft) arrived before it."""
        deadline = time.time() + timeout
        others = 0
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                return None, others
            msg = master.recv_match(
                type="HEARTBEAT", blocking=True, timeout=min(remaining, 1.0)
            )
            if msg is None:
                continue
            if is_vehicle_heartbeat(msg):
                return msg, others
            others += 1

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
            self._autopilot = None
            self._vehicle_type = None
            self._mission_kind = None
            self._telemetry_at = 0.0
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
                self._maybe_request_streams(now)

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

    def _maybe_request_streams(self, now: float) -> None:
        """Ask for telemetry again while none is arriving.

        One request at connect is not enough on a real aircraft: a telemetry
        radio drops packets, and a flight controller that reboots mid-session
        comes back sending heartbeats only. Until position and status flow,
        keep asking every few seconds.
        """
        with self._state_lock:
            if self._master is None:
                return
            quiet = now - self._telemetry_at >= STREAM_RETRY_S
            due = now - self._stream_request_at >= STREAM_RETRY_S
        if quiet and due:
            self._request_streams()

    def _dispatch(self, msg, msg_type: str):
        """Hand the message to any request thread waiting for it."""
        with self._state_lock:
            for subscription in self._subscriptions:
                if _matches(subscription, msg, msg_type):
                    subscription.queue.put(msg)

            if not self._waiters:
                return
            still_waiting = []
            for waiter in self._waiters:
                if _matches(waiter, msg, msg_type):
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

    def _discard(self, waiter: _Waiter) -> None:
        with self._state_lock:
            if waiter in self._waiters:
                self._waiters.remove(waiter)

    def _wait(self, waiter: _Waiter, timeout: float):
        """Block on a registered waiter; None when nothing matched in time."""
        if not waiter.event.wait(timeout):
            self._discard(waiter)
            return None
        return waiter.message

    def _expect(self, types, timeout: float = 5.0, predicate=None):
        """Register and wait in one step — only for unsolicited messages
        (heartbeats), never for a reply to something we are about to send."""
        return self._wait(self._register(types, predicate), timeout)

    def _subscribe(self, types, predicate=None) -> _Subscription:
        subscription = _Subscription(types, predicate)
        with self._state_lock:
            if self._master is None:
                raise MavlinkError("Not connected to a vehicle.")
            self._subscriptions.append(subscription)
        return subscription

    def _unsubscribe(self, subscription: _Subscription) -> None:
        with self._state_lock:
            if subscription in self._subscriptions:
                self._subscriptions.remove(subscription)

    # ── who is talking ────────────────────────────────────────────────────

    def _from_vehicle(self, msg, component: bool = True) -> bool:
        """Did `msg` come from the aircraft we locked onto?

        With ``component=False`` any part of that aircraft counts (a camera, a
        companion computer); otherwise it must be the flight controller.
        """
        try:
            if msg.get_srcSystem() != self._target_system:
                return False
            return not component or msg.get_srcComponent() == self._target_component
        except Exception:
            return False

    def _mission_reply(self, msg) -> bool:
        """A mission-protocol message from our vehicle, meant for us."""
        if not self._from_vehicle(msg, component=False):
            return False
        # Requests and acks name the station they answer. With another ground
        # station on the link, its own transfer must not be taken for ours.
        target = getattr(msg, "target_system", 0) or 0
        return target in (0, self._source_system)

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

            if msg_type == "STATUSTEXT":
                # Any part of the aircraft may explain itself (the autopilot,
                # a camera, a companion computer); other systems may not.
                if not self._from_vehicle(msg, component=False):
                    return
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
                return

            # Everything else must come from the flight controller itself. A
            # companion computer's heartbeat (disarmed, no mode) or another
            # device's position would otherwise overwrite the aircraft's.
            if not self._from_vehicle(msg):
                return

            if msg_type == "HEARTBEAT":
                self._last_heartbeat = time.time()
                telemetry["armed"] = bool(
                    msg.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED
                )
                telemetry["mode"] = self._mode_name(msg)
                telemetry["system_status"] = self._enum_name(
                    "MAV_STATE", msg.system_status, "MAV_STATE_"
                )

            elif msg_type == "GLOBAL_POSITION_INT":
                self._telemetry_at = time.time()
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
                self._telemetry_at = time.time()
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

    def _mode_map(self) -> Dict:
        """Flight-mode name -> number for *our* vehicle.

        Worked out from the vehicle's own heartbeat rather than asked of
        pymavlink, whose answer follows whichever system it decided was the
        vehicle — the same one, on a well-behaved link, but not a guarantee.
        """
        if (
            mavutil is not None
            and self._autopilot == AUTOPILOT_ARDUPILOT
            and self._vehicle_type is not None
        ):
            try:
                mapping = mavutil.mode_mapping_byname(self._vehicle_type)
                if mapping:
                    return dict(mapping)
            except Exception:
                pass
        master = self._master
        if master is None:
            return {}
        try:
            return dict(master.mode_mapping() or {})
        except Exception:
            return {}

    def _mode_name(self, heartbeat) -> Optional[str]:
        if self._autopilot == AUTOPILOT_PX4 and mavutil is not None:
            try:
                return mavutil.mode_string_v10(heartbeat)
            except Exception:
                return None
        for name, number in self._mode_map().items():
            if number == heartbeat.custom_mode:
                return name
        return None

    def snapshot(self) -> Dict:
        """Link state + latest telemetry, as sent to the app."""
        with self._state_lock:
            connected = self._master is not None
            now = time.time()
            age = now - self._last_heartbeat if self._last_heartbeat else None
            autopilot = self._autopilot if connected else None
            return {
                "available": mavutil is not None,
                "connected": connected,
                "alive": connected and age is not None
                and age < HEARTBEAT_TIMEOUT_S,
                "url": self._url,
                "target_system": self._target_system if connected else None,
                # Our own GCS address — worth surfacing when another ground
                # station shares the link and IDs need to differ.
                "source_system": self._source_system if connected else None,
                # What the aircraft says it is. The app flies ArduPilot only;
                # anything else still gets telemetry.
                "autopilot": (
                    _AUTOPILOT_NAMES.get(autopilot, "other")
                    if autopilot is not None else None
                ),
                "vehicle_type": (
                    self._enum_name("MAV_TYPE", self._vehicle_type, "MAV_TYPE_")
                    if connected and self._vehicle_type is not None else None
                ),
                "flight_control_supported": bool(
                    connected and autopilot in (None, AUTOPILOT_ARDUPILOT)
                ),
                "mission_kind": self._mission_kind if connected else None,
                "heartbeat_age_s": round(age, 2) if age is not None else None,
                "uptime_s": round(now - self._connected_at, 1)
                if connected else None,
                "telemetry": dict(self._telemetry),
                # age_s rather than a timestamp: the phone's clock is not the
                # server's, and "how long ago" is what the screen needs.
                "messages": [
                    {**message, "age_s": round(now - message["at"], 1)}
                    for message in self._statustexts[-8:]
                ],
            }

    # ── commands ──────────────────────────────────────────────────────────

    def _require_link(self):
        if mavutil is None:
            raise MavlinkError(
                "pymavlink is not installed on the server. "
                "Run: pip install pymavlink",
                503,
            )
        if self._master is None:
            raise MavlinkError(
                "No vehicle connected. Connect the MAVLink link first."
            )
        return self._master

    def _require_flight_control(self) -> None:
        """Refuse to move an aircraft whose autopilot the app does not fly."""
        with self._state_lock:
            autopilot = self._autopilot
        if autopilot is None or autopilot == AUTOPILOT_ARDUPILOT:
            return
        name = "PX4" if autopilot == AUTOPILOT_PX4 else f"autopilot type {autopilot}"
        raise MavlinkError(
            f"This vehicle runs {name}. AgriVision's missions, launch sequence "
            "and spray commands are written for ArduPilot (ArduCopter), so the "
            "app will not fly it. Telemetry still works; fly this aircraft "
            "from its own ground station.",
            409,
        )

    def _require_alive(self, doing: str) -> None:
        if not self.is_alive:
            raise MavlinkError(
                "The vehicle has stopped sending heartbeats, so nothing will be "
                f"{doing}. Check the telemetry link and try again.",
                409,
            )

    def _reasons_since(self, since: float, wait: float = 0.4) -> str:
        """What the autopilot said (warnings and worse) since `since`.

        ArduPilot explains a refusal in a STATUSTEXT — "PreArm: GPS not
        healthy", "Arm: Throttle too high" — sent around the same moment as
        the bare "failed". The code says nothing the operator can act on; the
        text says exactly what to do. Waits briefly, as the text can trail the
        acknowledgement.
        """
        deadline = time.time() + wait
        while True:
            with self._state_lock:
                texts = [
                    m["text"] for m in self._statustexts
                    if m["at"] >= since and m["severity"] <= 4 and m["text"]
                ]
            if texts or time.time() >= deadline:
                break
            time.sleep(0.05)

        unique: List[str] = []
        for text in texts:
            if text not in unique:
                unique.append(text)
        return "; ".join(unique[-3:])

    def _with_reason(self, message: str, since: float, wait: float = 0.4) -> str:
        reason = self._reasons_since(since, wait)
        return f"{message} Vehicle says: {reason}" if reason else message

    def _request_streams(self):
        """Ask for a decent telemetry rate (older ArduPilot needs the nudge)."""
        master = self._master
        if master is None:
            return
        with self._state_lock:
            self._stream_request_at = time.time()
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
            ("COMMAND_ACK",),
            predicate=lambda m: m.command == command
            and self._from_vehicle(m, component=False),
        )
        sent_at = time.time()
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
            raise MavlinkError(self._with_reason(
                f"No acknowledgement for {label} within {timeout:.0f}s.",
                sent_at, wait=0.0,
            ))

        result = _MAV_RESULT.get(ack.result, f"result_{ack.result}")
        if ack.result not in (0, 5):  # ACCEPTED / IN_PROGRESS
            raise MavlinkError(
                self._with_reason(f"Vehicle rejected {label} ({result}).", sent_at),
                409,
            )
        return {"command": label, "result": result}

    def set_mode(self, mode: str, timeout: float = 5.0) -> Dict:
        """Switch flight mode by name (GUIDED, AUTO, RTL, LAND, BRAKE…)."""
        master = self._require_link()
        self._require_flight_control()
        mode = str(mode).upper().strip()

        mapping = self._mode_map()
        if mode not in mapping:
            raise MavlinkError(
                f"Unknown flight mode '{mode}'. "
                f"Vehicle supports: {', '.join(sorted(mapping))}."
            )

        with self._state_lock:
            if self._telemetry.get("mode") == mode:
                return {"command": "set_mode", "mode": mode, "result": "already"}

        # ArduPilot answers SET_MODE with a COMMAND_ACK — the one place it says
        # a mode was refused, next to a STATUSTEXT saying why ("requires
        # position"). Listened for, not relied on: whether the mode actually
        # changed is still settled by the heartbeat.
        refusal = self._register(
            ("COMMAND_ACK",),
            predicate=lambda m: m.command == _SET_MODE_ACK
            and m.result not in (0, 5)
            and self._from_vehicle(m, component=False),
        )
        sent_at = time.time()
        try:
            with self._send_lock:
                master.mav.set_mode_send(
                    self._target_system,
                    mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                    mapping[mode],
                )

            deadline = time.time() + timeout
            while time.time() < deadline:
                if refusal.event.is_set():
                    result = _MAV_RESULT.get(refusal.message.result, "refused")
                    raise MavlinkError(
                        self._with_reason(
                            f"Vehicle refused to switch to {mode} ({result}).",
                            sent_at,
                        ),
                        409,
                    )
                self._expect(
                    ("HEARTBEAT",), timeout=0.5, predicate=self._from_vehicle
                )
                with self._state_lock:
                    if self._telemetry.get("mode") == mode:
                        return {
                            "command": "set_mode", "mode": mode, "result": "accepted",
                        }
        finally:
            self._discard(refusal)

        raise MavlinkError(self._with_reason(
            f"Vehicle did not switch to {mode} within {timeout:.0f}s.",
            sent_at, wait=0.0,
        ))

    def arm(self, force: bool = False) -> Dict:
        self._require_link()
        self._require_flight_control()
        if force and not force_allowed():
            raise MavlinkError(
                "Force-arming skips the autopilot's pre-arm safety checks, so it "
                "is switched off. It is for bench testing only: set "
                "MAVLINK_ALLOW_FORCE_ARM=1 on the server to allow it.",
                403,
            )
        # 21196 is the ArduPilot "force" magic number (skips pre-arm checks).
        return self.send_command_long(
            mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
            params=(1, 21196 if force else 0),
            label="arm",
            timeout=8.0,
        )

    def disarm(self, force: bool = False) -> Dict:
        self._require_link()
        self._require_flight_control()
        if force and not force_allowed():
            raise MavlinkError(
                "Force-disarming stops the motors even in the air, so it is "
                "switched off. It is for bench testing only: set "
                "MAVLINK_ALLOW_FORCE_ARM=1 on the server to allow it.",
                403,
            )
        return self.send_command_long(
            mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
            params=(0, 21196 if force else 0),
            label="disarm",
        )

    def takeoff(self, altitude_m: float) -> Dict:
        self._require_link()
        self._require_flight_control()
        return self.send_command_long(
            mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
            params=(0, 0, 0, 0, 0, 0, float(altitude_m)),
            label="takeoff",
        )

    def return_to_launch(self) -> Dict:
        return self.set_mode("RTL")

    def land(self) -> Dict:
        return self.set_mode("LAND")

    # How to stop and stay put without a pilot, best first. BRAKE (Copter)
    # ignores the sticks. LOITER does not: in Copter it climbs or sinks with
    # the throttle stick, and during an autonomous flight that stick usually
    # sits at the bottom — "hold" would bring the aircraft down into the crop.
    # So LOITER is only the fallback, for Plane (which circles on
    # autothrottle), and HOLD is Rover's.
    HOLD_MODES = ("BRAKE", "LOITER", "HOLD")

    def hold(self) -> Dict:
        """Pause the mission: stop and hold position."""
        self._require_link()
        mapping = self._mode_map()
        for name in self.HOLD_MODES:
            if name in mapping:
                return self.set_mode(name)
        raise MavlinkError("Vehicle has no brake, loiter or hold mode.")

    def interrupt(self) -> None:
        """Record that a stop-type command (RTL, land, hold, spray stop) is
        being sent.

        A launch in progress checks this between its steps and gives up.
        Otherwise its last step, MISSION_START, would switch the aircraft
        straight back to AUTO a moment after the operator told it to come home.
        """
        with self._state_lock:
            self._interrupts += 1

    def preflight_problems(self) -> List[str]:
        """Reasons not to launch that can be seen before the autopilot's own
        pre-arm checks — the ones whose fix is outside the aircraft: wait for a
        GPS fix, swap the battery. ArduPilot still has the last word."""
        problems: List[str] = []
        with self._state_lock:
            telemetry = dict(self._telemetry)

        if not self.is_alive:
            problems.append("The vehicle is not sending heartbeats.")

        fix = telemetry.get("gps_fix")
        if fix is None or fix < 3:
            satellites = telemetry.get("satellites")
            problems.append(
                "No 3-D GPS fix yet ("
                + _GPS_FIX.get(fix, "no GPS data")
                + (f", {satellites} satellites" if satellites is not None else "")
                + "). Wait in the open until the fix comes in."
            )

        battery = telemetry.get("battery_percent")
        minimum = _env_int("MAVLINK_MIN_LAUNCH_BATTERY", MIN_LAUNCH_BATTERY_PCT)
        if battery is not None and 0 <= battery < minimum:
            problems.append(
                f"Battery is at {battery}%, below the {minimum}% needed to launch."
            )
        return problems

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

        A Return Home / Land / Hold sent while this runs cancels it between
        steps (see :meth:`interrupt`).
        """
        self._require_link()
        self._require_flight_control()
        steps = []

        with self._state_lock:
            already_armed = self._telemetry.get("armed", False)
            interrupts = self._interrupts

        def still_wanted():
            with self._state_lock:
                if self._interrupts != interrupts:
                    raise MavlinkError(
                        "Launch cancelled: a Return Home, Land or Hold was sent "
                        "while it was starting.",
                        409,
                    )

        if not already_armed:
            problems = self.preflight_problems()
            if problems:
                raise MavlinkError("Not launching. " + " ".join(problems), 409)

            mapping = self._mode_map()
            arming_mode = next(
                (mode for mode in self.ARMABLE_MODES if mode in mapping), None
            )
            if arming_mode is None:
                raise MavlinkError(
                    "Vehicle offers none of "
                    f"{', '.join(self.ARMABLE_MODES)} to arm from."
                )
            steps.append(self.set_mode(arming_mode))
            still_wanted()
            steps.append(self.arm())
            still_wanted()
        else:
            self._require_alive("launched")

        steps.append(self.set_mode("AUTO"))
        still_wanted()
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
        timeout: Optional[float] = None,
    ) -> Dict:
        """Write the waypoint list to the vehicle using the mission protocol."""
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
        return self.upload_items(items, timeout=timeout, kind="survey")

    def upload_items(
        self,
        items: List[Dict],
        timeout: Optional[float] = None,
        kind: str = "survey",
    ) -> Dict:
        """Write an already-built mission item list to the vehicle.

        Sequence: clear the old mission → announce the new count → serve every
        MISSION_REQUEST the vehicle asks for → wait for MISSION_ACK.

        Split out from :meth:`upload_mission` so a mission that is *not* a
        plain survey — a spray run, which interleaves valve commands with its
        waypoints — goes up over exactly the same, already-proven handshake
        instead of a second copy of it. ``kind`` records which it was.
        """
        master = self._require_link()
        self._require_flight_control()
        self._require_alive("uploaded")
        with self._state_lock:
            armed = bool(self._telemetry.get("armed"))
        if armed:
            raise MavlinkError(
                "The vehicle is armed. Land and disarm it before loading a new "
                "mission: replacing the plan of an aircraft that is flying it "
                "changes where it goes next, in mid-air.",
                409,
            )

        if not items:
            raise ValueError("Mission has no items to upload.")
        count = len(items)
        if timeout is None:
            # A telemetry radio turns an item round in a tenth of a second or
            # so and re-asks for any it lost; a fixed 30 s runs out on a big
            # spray mission long before the radio does.
            timeout = max(30.0, 10.0 + 0.5 * count)

        # One queue for the whole exchange, opened before the first send: the
        # vehicle answers a mission message immediately, and nothing it says
        # between two of our messages may be lost.
        subscription = self._subscribe(
            ("MISSION_REQUEST", "MISSION_REQUEST_INT", "MISSION_ACK"),
            predicate=self._mission_reply,
        )
        try:
            # Clear first so a shorter new mission can't leave stale tail items.
            with self._send_lock:
                master.mav.mission_clear_all_send(
                    self._target_system, self._target_component
                )
            self._next_of(subscription, "MISSION_ACK", 3.0)

            with self._send_lock:
                master.mav.mission_count_send(
                    self._target_system,
                    self._target_component,
                    count,
                    MISSION_TYPE_MISSION,
                )

            sent = set()
            deadline = time.time() + timeout
            while True:
                remaining = deadline - time.time()
                if remaining <= 0:
                    raise MavlinkError(
                        f"Mission upload timed out ({len(sent)}/{count} items sent)."
                    )
                msg = subscription.next(min(5.0, remaining))
                if msg is None:
                    raise MavlinkError(
                        f"Vehicle stopped requesting mission items "
                        f"({len(sent)}/{count} sent)."
                    )

                if msg.get_type() == "MISSION_ACK":
                    if msg.type == 0:  # MAV_MISSION_ACCEPTED
                        if len(sent) >= count:
                            break
                        # ACCEPTED before every item has gone up is not this
                        # upload's answer: over a slow radio it is usually the
                        # clear-all's reply arriving late. Keep serving.
                        continue
                    raise MavlinkError(
                        "Vehicle rejected the mission: it reported "
                        f"{_MISSION_RESULT.get(msg.type, 'an error')} "
                        f"(code {msg.type})."
                    )

                seq = int(msg.seq)
                if 0 <= seq < count:
                    self._send_mission_item(items[seq])
                    sent.add(seq)
        finally:
            self._unsubscribe(subscription)

        # Point the vehicle at the first real command so AUTO starts from the
        # top. Seq 0 is ArduPilot's home slot, which it won't take as current.
        if count > 1:
            with self._send_lock:
                master.mav.mission_set_current_send(
                    self._target_system, self._target_component, 1
                )

        with self._state_lock:
            self._telemetry["mission_items"] = count
            self._mission_kind = kind

        logger.info("MAVLink: uploaded %d mission items (%s)", count, kind)
        return {"uploaded": count, "items": items}

    @staticmethod
    def _next_of(subscription: _Subscription, msg_type: str, timeout: float):
        """The next queued message of one type; others are skipped."""
        deadline = time.time() + timeout
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                return None
            msg = subscription.next(remaining)
            if msg is None or msg.get_type() == msg_type:
                return msg

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
