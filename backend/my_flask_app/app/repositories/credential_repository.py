from app.api.models.credential import PilotCredential
from app.core.database import db


class CredentialRepository:

    @staticmethod
    def create(credential):
        db.session.add(credential)
        db.session.commit()
        return credential

    @staticmethod
    def get_by_id(credential_id):
        return PilotCredential.query.get(credential_id)

    @staticmethod
    def list_for_user(user_id):
        """A pilot's credentials, soonest expiry first.

        Ordering by expiry puts whatever is about to lapse at the top of the
        Profile screen, which is the only ordering an operator cares about.
        Never-expiring entries sort last.
        """
        credentials = (
            PilotCredential.query.filter_by(user_id=user_id)
            .order_by(PilotCredential.id.asc())
            .all()
        )
        return sorted(
            credentials,
            key=lambda c: (c.expires_on is None, c.expires_on or c.id),
        )

    @staticmethod
    def delete(credential):
        db.session.delete(credential)
        db.session.commit()

    @staticmethod
    def save():
        db.session.commit()
