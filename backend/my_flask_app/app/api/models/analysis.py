import json

from app.core.database import db


class AnalysisRecord(db.Model):
    """One persisted multispectral analysis run (feeds Reports history)."""

    __tablename__ = "analysis_records"

    id = db.Column(db.Integer, primary_key=True)

    # The preprocessing job folder the previews/risk map were written under.
    job_id = db.Column(db.String(64), nullable=True)

    # Anonymous runs are allowed (the analyze endpoint has no login gate).
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    field_name = db.Column(db.String(120), nullable=True)

    primary_index = db.Column(db.String(20), nullable=True)

    health_score = db.Column(db.Float, nullable=True)

    health_label = db.Column(db.String(30), nullable=True)

    calibrated = db.Column(db.Boolean, default=False)

    # Area fraction (0..1) per risk band, denormalised for cheap listing.
    risk_high = db.Column(db.Float, default=0.0)
    risk_medium = db.Column(db.Float, default=0.0)
    risk_low = db.Column(db.Float, default=0.0)

    # The full analysis response (report, risk, action plan, output URLs).
    summary = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    alerts = db.relationship(
        "AlertRecord", backref="analysis", lazy=True, cascade="all, delete-orphan"
    )

    def summary_dict(self):
        try:
            return json.loads(self.summary) if self.summary else {}
        except (TypeError, ValueError):
            return {}

    def to_dict(self, include_summary=False):
        data = {
            "id": self.id,
            "job_id": self.job_id,
            "user_id": self.user_id,
            "field_name": self.field_name,
            "primary_index": self.primary_index,
            "health_score": self.health_score,
            "health_label": self.health_label,
            "calibrated": bool(self.calibrated),
            "risk_distribution": {
                "high": self.risk_high,
                "medium": self.risk_medium,
                "low": self.risk_low,
            },
            "alert_count": len(self.alerts),
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if include_summary:
            data["summary"] = self.summary_dict()
        return data


class AlertRecord(db.Model):
    """A stress/risk flag raised by an analysis run (feeds the AI Alerts tab)."""

    __tablename__ = "alert_records"

    id = db.Column(db.Integer, primary_key=True)

    analysis_id = db.Column(
        db.Integer, db.ForeignKey("analysis_records.id"), nullable=False
    )

    title = db.Column(db.String(255), nullable=False)

    # high | medium | low
    severity = db.Column(db.String(10), default="medium")

    # Vegetation index that raised the flag (e.g. 'ndvi', 'ndre').
    index_key = db.Column(db.String(20), nullable=True)

    location = db.Column(db.String(120), nullable=True)

    # Human-readable share of the field affected, e.g. '38% of field'.
    area = db.Column(db.String(40), nullable=True)

    is_active = db.Column(db.Boolean, default=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    def to_dict(self):
        return {
            "id": self.id,
            "analysis_id": self.analysis_id,
            "title": self.title,
            "severity": self.severity,
            "index_key": self.index_key,
            "location": self.location,
            "area": self.area,
            "is_active": bool(self.is_active),
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
