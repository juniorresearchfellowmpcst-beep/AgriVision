"""Service layer for drone pairing and live status.

Static methods returning (response_dict, status_code), matching the other
services. The mobile app's Home screen and Profile screen read drone status
from here; pairing assigns a drone to the signed-in user.
"""

from datetime import datetime

from app.api.models.drone import Drone
from app.repositories.drone_repository import DroneRepository


class DroneService:

    @staticmethod
    def _ensure_seed():
        """Dev convenience: seed one demo unit so a fresh install has a drone
        to pair/fly before real hardware is registered."""
        if DroneRepository.count() > 0:
            return
        DroneRepository.create(
            Drone(
                name="AgriDrone Unit GCS-04",
                serial_number="ADU-2024-04-7832",
                model="AgriDrone GCS",
                frequency="2.4 GHz",
                status="available",
                is_connected=True,
                battery_percent=84,
                tank_percent=63,
                gps_satellites=18,
                signal_dbm=-68,
                total_flights=312,
                last_seen=datetime.utcnow(),
            )
        )

    @staticmethod
    def list_drones(user_id=None):
        """All registered drones, flagging the one paired to this user."""
        DroneService._ensure_seed()
        drones = DroneRepository.list_all()
        return {
            "status": "ok",
            "drones": [
                {**d.to_dict(), "is_mine": user_id is not None and d.owner_id == user_id}
                for d in drones
            ],
        }, 200

    @staticmethod
    def get_status(user_id=None):
        """The drone the app should display: the user's paired unit, or the
        first available one when nothing is paired yet."""
        DroneService._ensure_seed()

        drone = None
        if user_id is not None:
            drone = DroneRepository.get_by_owner(user_id)
        if drone is None:
            drones = DroneRepository.list_all()
            drone = drones[0] if drones else None

        if drone is None:
            return {"status": "error", "message": "No drone registered."}, 404

        return {"status": "ok", "drone": drone.to_dict()}, 200

    @staticmethod
    def pair(user_id, drone_id=None, serial_number=None):
        DroneService._ensure_seed()

        drone = None
        if drone_id is not None:
            drone = DroneRepository.get_by_id(drone_id)
        elif serial_number:
            drone = DroneRepository.get_by_serial(serial_number)

        if drone is None:
            return {"status": "error", "message": "Drone not found."}, 404

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
        drone.last_seen = datetime.utcnow()
        DroneRepository.save()

        return {
            "status": "ok",
            "message": f"Paired with {drone.name}.",
            "drone": drone.to_dict(),
        }, 200

    @staticmethod
    def unpair(user_id):
        drone = DroneRepository.get_by_owner(user_id)
        if drone is None:
            return {"status": "error", "message": "No drone paired."}, 404

        drone.owner_id = None
        drone.status = "available"
        DroneRepository.save()
        return {"status": "ok", "message": "Drone unpaired.", "drone": drone.to_dict()}, 200

    @staticmethod
    def update_telemetry(drone_id, fields):
        """Apply validated telemetry fields (battery, tank, gps, ...)."""
        drone = DroneRepository.get_by_id(drone_id)
        if drone is None:
            return {"status": "error", "message": "Drone not found."}, 404

        for key, value in fields.items():
            setattr(drone, key, value)
        drone.last_seen = datetime.utcnow()
        DroneRepository.save()

        return {"status": "ok", "drone": drone.to_dict()}, 200
