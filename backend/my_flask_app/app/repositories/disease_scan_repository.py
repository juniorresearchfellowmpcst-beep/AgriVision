from app.api.models.disease_scan import DiseaseScan
from app.core.database import db


class DiseaseScanRepository:

    @staticmethod
    def create(scan):
        db.session.add(scan)
        db.session.commit()
        return scan

    @staticmethod
    def get_by_id(scan_id):
        return DiseaseScan.query.get(scan_id)

    @staticmethod
    def list_scans(user_id=None, limit=50):
        """Newest first. Anonymous scans are visible to everyone; a signed-in
        user additionally sees their own — same rule as mission history.

        The id breaks ties on created_at: SQLite stores it to the second, and
        an operator photographing several leaves in a row lands them all in the
        same second, which would otherwise come back in arbitrary order.
        """
        query = DiseaseScan.query
        if user_id is not None:
            query = query.filter(
                (DiseaseScan.user_id == user_id) | (DiseaseScan.user_id.is_(None))
            )
        return (
            query.order_by(DiseaseScan.created_at.desc(), DiseaseScan.id.desc())
            .limit(limit)
            .all()
        )

    @staticmethod
    def count_for_user(user_id=None):
        query = DiseaseScan.query
        if user_id is not None:
            query = query.filter(
                (DiseaseScan.user_id == user_id) | (DiseaseScan.user_id.is_(None))
            )
        return query.count()

    @staticmethod
    def save():
        db.session.commit()
