from app.core.database import db


class Drone(db.Model):
    """A drone / GCS unit that can be paired to a user and flown on missions."""

    __tablename__ = "drones"

    id = db.Column(db.Integer, primary_key=True)

    name = db.Column(db.String(100), nullable=False)

    serial_number = db.Column(db.String(100), unique=True, nullable=False)

    model = db.Column(db.String(100), nullable=True)

    frequency = db.Column(db.String(20), default="2.4 GHz")

    # Owner is optional: an unpaired drone is available to any user.
    owner_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    # available | paired | flying | offline
    status = db.Column(db.String(20), default="available")

    is_connected = db.Column(db.Boolean, default=False)

    battery_percent = db.Column(db.Integer, default=100)

    tank_percent = db.Column(db.Integer, default=100)

    gps_satellites = db.Column(db.Integer, default=0)

    signal_dbm = db.Column(db.Integer, nullable=True)

    total_flights = db.Column(db.Integer, default=0)

    last_seen = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "serial_number": self.serial_number,
            "model": self.model,
            "frequency": self.frequency,
            "owner_id": self.owner_id,
            "status": self.status,
            "is_connected": bool(self.is_connected),
            "battery_percent": self.battery_percent,
            "tank_percent": self.tank_percent,
            "gps_satellites": self.gps_satellites,
            "signal_dbm": self.signal_dbm,
            "total_flights": self.total_flights,
            "last_seen": self.last_seen.isoformat() if self.last_seen else None,
        }
