import json

from app.core.database import db


class DiseaseScan(db.Model):
    """One plant-disease identification, kept so scans become field history.

    Without this the diagnosis vanished the moment the operator left the
    screen. Persisting it lets the Disease tab show what was already found in
    this block, and gives the agronomist a record of when a problem first
    appeared rather than only that it exists now.
    """

    __tablename__ = "disease_scans"

    id = db.Column(db.Integer, primary_key=True)

    # Scanning is open to anonymous users, same as the analyzer.
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    # Knowledge-base id, e.g. 'fungal_leaf_spot'.
    condition_id = db.Column(db.String(60), nullable=True)

    condition_name = db.Column(db.String(120), nullable=True)

    # healthy | mild | moderate | severe
    severity = db.Column(db.String(20), nullable=True)

    confidence = db.Column(db.Float, default=0.0)

    # 'model' when a trained classifier answered, 'heuristic' otherwise —
    # worth recording, because the two are not equally trustworthy.
    engine = db.Column(db.String(20), nullable=True)

    is_healthy = db.Column(db.Boolean, default=False)

    filename = db.Column(db.String(255), nullable=True)

    # Optional block/field the operator was standing in.
    field_name = db.Column(db.String(120), nullable=True)

    # The full identify() response, so history can show the same detail the
    # live result did without re-running the model.
    detail = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    def detail_dict(self):
        try:
            return json.loads(self.detail) if self.detail else {}
        except (TypeError, ValueError):
            return {}

    def to_dict(self, include_detail=False):
        data = {
            "id": self.id,
            "user_id": self.user_id,
            "condition_id": self.condition_id,
            "condition_name": self.condition_name,
            "severity": self.severity,
            "confidence": self.confidence,
            "engine": self.engine,
            "is_healthy": bool(self.is_healthy),
            "filename": self.filename,
            "field_name": self.field_name,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if include_detail:
            data["detail"] = self.detail_dict()
        return data
