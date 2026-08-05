from app.api.models.spray import SprayPrescription
from app.core.database import db


class SprayRepository:

    @staticmethod
    def create(prescription):
        db.session.add(prescription)
        db.session.commit()
        return prescription

    @staticmethod
    def get_by_id(prescription_id):
        return SprayPrescription.query.get(prescription_id)

    @staticmethod
    def list_prescriptions(user_id=None, session_id=None, limit=50):
        """Newest first. Anonymous rows are visible to everyone, same rule as
        the rest of the app; id DESC breaks same-second ties."""
        query = SprayPrescription.query
        if user_id is not None:
            query = query.filter(
                (SprayPrescription.user_id == user_id)
                | (SprayPrescription.user_id.is_(None))
            )
        if session_id:
            query = query.filter(SprayPrescription.session_id == session_id)
        return (
            query.order_by(
                SprayPrescription.created_at.desc(), SprayPrescription.id.desc()
            )
            .limit(limit)
            .all()
        )

    @staticmethod
    def save():
        db.session.commit()
