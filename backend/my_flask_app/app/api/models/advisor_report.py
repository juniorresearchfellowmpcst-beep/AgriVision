"""Reports of crop-advisor answers a user found harmful, wrong or offensive.

Google Play's AI-generated content policy requires an app that produces
content with generative AI to let people report offensive or harmful output
from inside the app. The advisor is that feature here -- its answers come from
Gemini -- so every answer carries a Report action, and this is where those
reports land for a person to review.

The answer text is stored because the conversation itself is not: the advisor
keeps no history on the server, so without a copy here a report would point at
nothing anyone could read.
"""

from app.core.database import db

# What a report can say. Short and concrete, so they can be counted.
REPORT_REASONS = ("harmful", "wrong", "offensive", "other")


class AdvisorReport(db.Model):
    __tablename__ = "advisor_reports"

    id = db.Column(db.Integer, primary_key=True)

    # Nullable: the advisor answers signed-out users too. Deleted with the
    # account when there is one.
    user_id = db.Column(
        db.Integer, db.ForeignKey("users.id"), nullable=True, index=True
    )

    reason = db.Column(db.String(20), nullable=False)
    note = db.Column(db.Text, nullable=True)

    question = db.Column(db.Text, nullable=True)
    answer = db.Column(db.Text, nullable=False)
    model = db.Column(db.String(80), nullable=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    def to_dict(self):
        return {
            "id": self.id,
            "reason": self.reason,
            "note": self.note,
            "question": self.question,
            "answer": self.answer,
            "model": self.model,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
