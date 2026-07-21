from app.api.models.analysis import AlertRecord, AnalysisRecord
from app.core.database import db


class AnalysisRepository:

    @staticmethod
    def create(record):
        db.session.add(record)
        db.session.commit()
        return record

    @staticmethod
    def get_by_id(record_id):
        return AnalysisRecord.query.get(record_id)

    @staticmethod
    def list_records(user_id=None, limit=50):
        """Newest first. Anonymous runs (user_id NULL) are visible to everyone;
        a signed-in user additionally sees their own runs."""
        query = AnalysisRecord.query
        if user_id is not None:
            query = query.filter(
                (AnalysisRecord.user_id == user_id)
                | (AnalysisRecord.user_id.is_(None))
            )
        return query.order_by(AnalysisRecord.created_at.desc()).limit(limit).all()

    @staticmethod
    def list_alerts(user_id=None, active_only=True, limit=100):
        query = AlertRecord.query.join(AnalysisRecord)
        if active_only:
            query = query.filter(AlertRecord.is_active.is_(True))
        if user_id is not None:
            query = query.filter(
                (AnalysisRecord.user_id == user_id)
                | (AnalysisRecord.user_id.is_(None))
            )
        return query.order_by(AlertRecord.created_at.desc()).limit(limit).all()

    @staticmethod
    def get_alert(alert_id):
        return AlertRecord.query.get(alert_id)

    @staticmethod
    def save():
        db.session.commit()
