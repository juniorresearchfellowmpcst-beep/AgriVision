import json

from app.core.database import db


class Mission(db.Model):
    """A planned (and possibly flown) survey mission over a field block."""

    __tablename__ = "missions"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    name = db.Column(db.String(120), nullable=False)

    # multispectral | scouting
    mode = db.Column(db.String(20), nullable=True)

    area_ha = db.Column(db.Float, nullable=True)

    altitude_m = db.Column(db.Float, nullable=True)

    speed_ms = db.Column(db.Float, nullable=True)

    overlap_pct = db.Column(db.Integer, nullable=True)

    line_spacing_m = db.Column(db.Float, nullable=True)

    # planned | in_progress | done | partial | aborted
    status = db.Column(db.String(20), default="planned")

    waypoint_count = db.Column(db.Integer, default=0)

    # JSON list of {lat, lon} (altitude comes from altitude_m).
    waypoints = db.Column(db.Text, nullable=True)

    duration_min = db.Column(db.Float, nullable=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    completed_at = db.Column(db.DateTime, nullable=True)

    def waypoints_list(self):
        try:
            return json.loads(self.waypoints) if self.waypoints else []
        except (TypeError, ValueError):
            return []

    def to_dict(self, include_waypoints=False):
        data = {
            "id": self.id,
            "user_id": self.user_id,
            "name": self.name,
            "mode": self.mode,
            "area_ha": self.area_ha,
            "altitude_m": self.altitude_m,
            "speed_ms": self.speed_ms,
            "overlap_pct": self.overlap_pct,
            "line_spacing_m": self.line_spacing_m,
            "status": self.status,
            "waypoint_count": self.waypoint_count,
            "duration_min": self.duration_min,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }
        if include_waypoints:
            data["waypoints"] = self.waypoints_list()
        return data
