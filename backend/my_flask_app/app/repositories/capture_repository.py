from app.api.models.capture import CameraFeed, CaptureFrame
from app.core.database import db


def _visible(query, model, user_id):
    """Own rows + anonymous rows, the same visibility rule as mission history."""
    if user_id is None:
        return query
    return query.filter((model.user_id == user_id) | (model.user_id.is_(None)))


class CameraRepository:

    @staticmethod
    def create(camera):
        db.session.add(camera)
        db.session.commit()
        return camera

    @staticmethod
    def get_by_id(camera_id):
        return CameraFeed.query.get(camera_id)

    @staticmethod
    def list_cameras(user_id=None, role=None, enabled_only=False):
        query = _visible(CameraFeed.query, CameraFeed, user_id)
        if role:
            query = query.filter(CameraFeed.role == role)
        if enabled_only:
            query = query.filter(CameraFeed.enabled.is_(True))
        return query.order_by(CameraFeed.role.asc(), CameraFeed.id.asc()).all()

    @staticmethod
    def delete(camera):
        db.session.delete(camera)
        db.session.commit()

    @staticmethod
    def save():
        db.session.commit()


class CaptureFrameRepository:

    @staticmethod
    def create_many(frames):
        db.session.add_all(frames)
        db.session.commit()
        return frames

    @staticmethod
    def get_by_id(frame_id):
        return CaptureFrame.query.get(frame_id)

    @staticmethod
    def list_frames(user_id=None, session_id=None, shot_id=None, role=None, limit=200):
        query = _visible(CaptureFrame.query, CaptureFrame, user_id)
        if session_id:
            query = query.filter(CaptureFrame.session_id == session_id)
        if shot_id:
            query = query.filter(CaptureFrame.shot_id == shot_id)
        if role:
            query = query.filter(CaptureFrame.role == role)
        # id DESC breaks ties: SQLite stores created_at to the second, and a
        # burst of shots on one pass lands several frames in the same second.
        return (
            query.order_by(CaptureFrame.created_at.desc(), CaptureFrame.id.desc())
            .limit(limit)
            .all()
        )

    @staticmethod
    def list_sessions(user_id=None, limit=30):
        """Distinct capture sessions, newest first, with a frame count each."""
        rows = (
            _visible(
                db.session.query(
                    CaptureFrame.session_id,
                    db.func.count(CaptureFrame.id).label("frames"),
                    db.func.count(db.func.distinct(CaptureFrame.shot_id)).label("shots"),
                    db.func.max(CaptureFrame.created_at).label("last_at"),
                    db.func.max(CaptureFrame.field_name).label("field_name"),
                ),
                CaptureFrame,
                user_id,
            )
            .group_by(CaptureFrame.session_id)
            .order_by(db.func.max(CaptureFrame.id).desc())
            .limit(limit)
            .all()
        )
        return [
            {
                "session_id": row.session_id,
                "frames": int(row.frames or 0),
                "shots": int(row.shots or 0),
                "field_name": row.field_name,
                "last_at": row.last_at.isoformat() if row.last_at else None,
            }
            for row in rows
        ]

    @staticmethod
    def save():
        db.session.commit()
