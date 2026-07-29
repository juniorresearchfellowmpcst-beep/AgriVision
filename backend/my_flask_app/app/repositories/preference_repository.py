from app.api.models.preference import UserPreference
from app.core.database import db


class PreferenceRepository:

    @staticmethod
    def get_or_create(user_id):
        """The user's preference row, created with defaults on first read."""
        preference = UserPreference.query.filter_by(user_id=user_id).first()
        if preference is None:
            preference = UserPreference(user_id=user_id)
            db.session.add(preference)
            db.session.commit()
        return preference

    @staticmethod
    def save():
        db.session.commit()
