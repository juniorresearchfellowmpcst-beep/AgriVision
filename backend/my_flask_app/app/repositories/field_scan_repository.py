from app.api.models.field_scan import FieldScanRecord
from app.core.database import db


class FieldScanRepository:

    @staticmethod
    def create(scan):
        db.session.add(scan)
        db.session.commit()
        return scan

    @staticmethod
    def create_many(scans):
        db.session.add_all(scans)
        db.session.commit()
        return scans

    @staticmethod
    def get_by_id(scan_id):
        return FieldScanRecord.query.get(scan_id)

    @staticmethod
    def list_scans(user_id=None, session_id=None, crop=None, limit=200):
        """Newest first; anonymous rows are visible to everyone.

        id DESC breaks ties because a low-pace pass records several frames a
        second and SQLite stores created_at only to the second.
        """
        query = FieldScanRecord.query
        if user_id is not None:
            query = query.filter(
                (FieldScanRecord.user_id == user_id)
                | (FieldScanRecord.user_id.is_(None))
            )
        if session_id:
            query = query.filter(FieldScanRecord.session_id == session_id)
        if crop:
            query = query.filter(FieldScanRecord.crop == crop)
        return (
            query.order_by(FieldScanRecord.created_at.desc(), FieldScanRecord.id.desc())
            .limit(limit)
            .all()
        )

    @staticmethod
    def list_sessions(user_id=None, limit=30):
        """Scanned sessions, newest first, for the field-scan history list."""
        query = db.session.query(
            FieldScanRecord.session_id,
            db.func.count(FieldScanRecord.id).label("frames"),
            db.func.avg(FieldScanRecord.weed_coverage).label("mean_weed"),
            db.func.max(FieldScanRecord.crop).label("crop"),
            db.func.max(FieldScanRecord.created_at).label("last_at"),
        ).filter(FieldScanRecord.session_id.isnot(None))

        if user_id is not None:
            query = query.filter(
                (FieldScanRecord.user_id == user_id)
                | (FieldScanRecord.user_id.is_(None))
            )

        rows = (
            query.group_by(FieldScanRecord.session_id)
            .order_by(db.func.max(FieldScanRecord.id).desc())
            .limit(limit)
            .all()
        )
        return [
            {
                "session_id": row.session_id,
                "frames": int(row.frames or 0),
                "crop": row.crop,
                "mean_weed_coverage": round(float(row.mean_weed or 0.0), 4),
                "last_at": row.last_at.isoformat() if row.last_at else None,
            }
            for row in rows
        ]

    @staticmethod
    def save():
        db.session.commit()
