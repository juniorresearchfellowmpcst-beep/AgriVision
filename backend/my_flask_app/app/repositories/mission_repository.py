from app.api.models.mission import Mission
from app.core.database import db


class MissionRepository:

    @staticmethod
    def create(mission):
        db.session.add(mission)
        db.session.commit()
        return mission

    @staticmethod
    def get_by_id(mission_id):
        return Mission.query.get(mission_id)

    @staticmethod
    def list_missions(user_id=None, limit=50):
        """Newest first. Anonymous missions are visible to everyone; a signed-in
        user additionally sees their own."""
        query = Mission.query
        if user_id is not None:
            query = query.filter(
                (Mission.user_id == user_id) | (Mission.user_id.is_(None))
            )
        return query.order_by(Mission.created_at.desc()).limit(limit).all()

    @staticmethod
    def stats_for_user(user_id):
        """(missions_flown, area_flown_ha, air_time_hours) over completed runs."""
        flown = Mission.query.filter(
            Mission.user_id == user_id,
            Mission.status.in_(("done", "partial")),
        ).all()
        missions_flown = len(flown)
        area = sum(m.area_ha or 0.0 for m in flown)
        minutes = sum(m.duration_min or 0.0 for m in flown)
        return missions_flown, round(area, 1), round(minutes / 60.0, 1)

    @staticmethod
    def save():
        db.session.commit()
