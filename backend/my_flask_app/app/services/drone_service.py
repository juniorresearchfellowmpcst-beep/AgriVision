"""Service layer for drone pairing and live status.

Static methods returning (response_dict, status_code), matching the other
services. The mobile app's Home screen and Profile screen read drone status
from here; pairing assigns a drone to the signed-in user.

Nothing here invents a drone. A fresh install has no hardware registered, so
``get_status`` answers with ``drone: null`` and the app shows its "connect a
drone" flow instead of numbers nobody's aircraft produced. The gauges
(battery, tank, GPS, signal) are only reported while they are actually being
fed — by the MAVLink link when a vehicle is on the wire, or by a recent
``PUT /api/drones/<id>/telemetry`` from the GCS. Once that goes quiet they
report ``None`` rather than the last value the database happens to hold.
"""

from datetime import datetime, timedelta

from app.api.models.drone import Drone
from app.mavlink import link
from app.repositories.drone_repository import DroneRepository

# How long a pushed telemetry reading stays believable. Past this the gauges
# read "unknown" — a two-hour-old battery percentage is not a battery level.
TELEMETRY_TTL_S = 120

# Gauges that describe the aircraft *right now* rather than what it is.
_VOLATILE_FIELDS = (
    "battery_percent",
    "tank_percent",
    "gps_satellites",
    "signal_dbm",
)


class DroneService:

    # ── live view ─────────────────────────────────────────────────────────

    @staticmethod
    def live_dict(drone):
        """The drone as it actually is: identity from the row, gauges from
        whatever is currently feeding them.

        Priority is MAVLink first (a vehicle on the link is the ground truth),
        then a recent telemetry push, then "unknown".
        """
        data = drone.to_dict()

        snapshot = link.snapshot()
        alive = bool(snapshot.get("alive"))
        telemetry = snapshot.get("telemetry") or {}

        fresh = (
            drone.last_seen is not None
            and datetime.utcnow() - drone.last_seen
            < timedelta(seconds=TELEMETRY_TTL_S)
        )

        # Start from "we don't know", then fill in what is being reported.
        if not fresh:
            for field in _VOLATILE_FIELDS:
                data[field] = None

        if alive:
            if telemetry.get("battery_percent") is not None:
                data["battery_percent"] = telemetry["battery_percent"]
            if telemetry.get("satellites") is not None:
                data["gps_satellites"] = telemetry["satellites"]

        data["is_connected"] = alive or (fresh and bool(drone.is_connected))
        data["telemetry_fresh"] = bool(alive or fresh)
        data["link"] = {
            "available": bool(snapshot.get("available")),
            "connected": bool(snapshot.get("connected")),
            "alive": alive,
            "url": snapshot.get("url"),
            "heartbeat_age_s": snapshot.get("heartbeat_age_s"),
        }
        if not data["is_connected"]:
            data["status"] = "offline" if drone.owner_id else "available"

        return data

    # ── queries ───────────────────────────────────────────────────────────

    @staticmethod
    def list_drones(user_id=None):
        """All registered drones, flagging the one paired to this user."""
        drones = DroneRepository.list_all()
        return {
            "status": "ok",
            "drones": [
                {
                    **DroneService.live_dict(d),
                    "is_mine": user_id is not None and d.owner_id == user_id,
                }
                for d in drones
            ],
        }, 200

    @staticmethod
    def get_status(user_id=None):
        """The drone the app should display: the signed-in user's paired unit.

        No paired unit is a normal state, not an error — it answers 200 with
        ``drone: null`` so the app can offer to connect one.
        """
        drone = (
            DroneRepository.get_by_owner(user_id) if user_id is not None else None
        )

        if drone is None:
            return {
                "status": "ok",
                "drone": None,
                "message": "No drone paired to this account.",
            }, 200

        return {"status": "ok", "drone": DroneService.live_dict(drone)}, 200

    # ── pairing ───────────────────────────────────────────────────────────

    @staticmethod
    def pair(user_id, drone_id=None, serial_number=None, name=None, model=None,
             frequency=None):
        """Bind a drone to this user, registering it on first sight.

        Pairing by a serial the server has never seen registers that aircraft
        — that is how a real unit enters the fleet, and it keeps a fresh
        install from being unusable without a hand-seeded row.
        """
        drone = None
        if drone_id is not None:
            drone = DroneRepository.get_by_id(drone_id)
            if drone is None:
                return {"status": "error", "message": "Drone not found."}, 404
        elif serial_number:
            drone = DroneRepository.get_by_serial(serial_number)

        # Whether this call created the aircraft or matched one already on
        # file. The caller needs to know: a typo'd serial silently registering
        # a second unit looks identical to pairing with the right one, which
        # makes pairing feel like it accepts anything.
        registered = drone is None

        if drone is None:
            if not serial_number:
                return {"status": "error", "message": "Drone not found."}, 404
            drone = DroneRepository.create(
                Drone(
                    name=(name or "").strip() or f"Drone {serial_number}",
                    serial_number=serial_number,
                    model=(model or "").strip() or None,
                    frequency=(frequency or "").strip() or "2.4 GHz",
                    status="available",
                    is_connected=False,
                    total_flights=0,
                )
            )

        if drone.owner_id is not None and drone.owner_id != user_id:
            return {
                "status": "error",
                "message": "Drone is already paired to another user.",
            }, 409

        # A user flies one unit at a time: release any previously paired drone.
        current = DroneRepository.get_by_owner(user_id)
        if current is not None and current.id != drone.id:
            current.owner_id = None
            current.status = "available"

        drone.owner_id = user_id
        drone.status = "paired"
        DroneRepository.save()

        return {
            "status": "ok",
            "registered": registered,
            "message": (
                f"New aircraft registered and paired: {drone.name} "
                f"({drone.serial_number}). If that serial is a typo, unpair "
                "and try again."
                if registered
                else f"Paired with {drone.name} ({drone.serial_number})."
            ),
            "drone": DroneService.live_dict(drone),
        }, 200

    @staticmethod
    def unpair(user_id):
        drone = DroneRepository.get_by_owner(user_id)
        if drone is None:
            return {"status": "error", "message": "No drone paired."}, 404

        drone.owner_id = None
        drone.status = "available"
        drone.is_connected = False
        DroneRepository.save()
        return {
            "status": "ok",
            "message": "Drone unpaired.",
            "drone": DroneService.live_dict(drone),
        }, 200

    @staticmethod
    def update_telemetry(drone_id, fields):
        """Apply validated telemetry fields (battery, tank, gps, ...).

        ``last_seen`` is what makes these readings count as current; without a
        refresh they age out of [TELEMETRY_TTL_S] and stop being reported.
        """
        drone = DroneRepository.get_by_id(drone_id)
        if drone is None:
            return {"status": "error", "message": "Drone not found."}, 404

        for key, value in fields.items():
            setattr(drone, key, value)
        drone.last_seen = datetime.utcnow()
        DroneRepository.save()

        return {"status": "ok", "drone": DroneService.live_dict(drone)}, 200
