from app.api.models.survey import SurveyRun
from app.core.database import db


class SurveyRepository:

    @staticmethod
    def create(run):
        db.session.add(run)
        db.session.commit()
        return run

    @staticmethod
    def get_by_id(run_id):
        return SurveyRun.query.get(run_id)

    @staticmethod
    def list_runs(user_id=None, status=None, limit=50):
        """Newest first. Anonymous rows are visible to everyone, matching the
        rest of the app; id DESC breaks same-second ties so the list order is
        stable between two reads."""
        query = SurveyRun.query
        if user_id is not None:
            query = query.filter(
                (SurveyRun.user_id == user_id) | (SurveyRun.user_id.is_(None))
            )
        if status:
            query = query.filter(SurveyRun.status == status)
        return (
            query.order_by(SurveyRun.created_at.desc(), SurveyRun.id.desc())
            .limit(limit)
            .all()
        )

    @staticmethod
    def active_for(user_id=None):
        """The run currently in the air, if any.

        Only one survey can be flying at a time -- there is one aircraft -- so
        the app asks for "the" active run rather than searching a list.
        """
        query = SurveyRun.query.filter(SurveyRun.status.in_(("flying", "planned")))
        if user_id is not None:
            query = query.filter(
                (SurveyRun.user_id == user_id) | (SurveyRun.user_id.is_(None))
            )
        return query.order_by(SurveyRun.id.desc()).first()

    @staticmethod
    def save():
        db.session.commit()
