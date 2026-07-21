from app.api.models.drone import Drone
from app.core.database import db


class DroneRepository:

    @staticmethod
    def get_by_id(drone_id):
        return Drone.query.get(drone_id)

    @staticmethod
    def get_by_serial(serial_number):
        return Drone.query.filter_by(serial_number=serial_number).first()

    @staticmethod
    def get_by_owner(owner_id):
        return Drone.query.filter_by(owner_id=owner_id).first()

    @staticmethod
    def list_all():
        return Drone.query.order_by(Drone.created_at.desc()).all()

    @staticmethod
    def count():
        return Drone.query.count()

    @staticmethod
    def create(drone):
        db.session.add(drone)
        db.session.commit()
        return drone

    @staticmethod
    def save(drone=None):
        """Commit pending changes (optionally adding a new instance)."""
        if drone is not None:
            db.session.add(drone)
        db.session.commit()
        return drone
