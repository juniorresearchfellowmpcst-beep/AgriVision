import json

from app.core.database import db

# Where a prescription is in the operator's decision, not the drone's flight.
# 'proposed' is the only state the backend can reach on its own — everything
# after it requires a human to have chosen something.
SPRAY_STATUSES = ("proposed", "approved", "uploaded", "sprayed", "cancelled")


class SprayPrescription(db.Model):
    """One K-means spray plan for one multispectral capture.

    Kept because a prescription is a record of a chemical decision: how much of
    the block was treated, at what rate, on the strength of which imagery. That
    is the paper trail behind "we used 40% less pesticide this season", and it
    is also what lets the operator re-open a plan they approved this morning
    instead of re-flying the field.
    """

    __tablename__ = "spray_prescriptions"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    # Which capture this was computed from.
    session_id = db.Column(db.String(60), nullable=True, index=True)
    shot_id = db.Column(db.String(60), nullable=True, index=True)

    field_name = db.Column(db.String(120), nullable=True)

    # Clustering inputs.
    index_key = db.Column(db.String(20), nullable=True)
    k = db.Column(db.Integer, default=3)

    # Share of the field each class covers, after patch cleanup (0..1).
    severe_fraction = db.Column(db.Float, default=0.0)
    moderate_fraction = db.Column(db.Float, default=0.0)
    healthy_fraction = db.Column(db.Float, default=0.0)

    patch_count = db.Column(db.Integer, default=0)
    field_ha = db.Column(db.Float, nullable=True)

    # The operator's choice, once made.
    chosen_option = db.Column(db.String(30), nullable=True)
    treated_fraction = db.Column(db.Float, nullable=True)
    saving_percent = db.Column(db.Integer, nullable=True)
    chemical_l = db.Column(db.Float, nullable=True)
    saved_l = db.Column(db.Float, nullable=True)

    status = db.Column(db.String(20), default="proposed")

    # Rendered prescription map, relative to the analysis output root.
    map_path = db.Column(db.String(300), nullable=True)

    # The full prescription payload, so the app can re-open the plan (patches,
    # options, coverage assumptions) without recomputing it.
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
            "session_id": self.session_id,
            "shot_id": self.shot_id,
            "field_name": self.field_name,
            "index": self.index_key,
            "k": self.k,
            "severity_fractions": {
                "severe": self.severe_fraction,
                "moderate": self.moderate_fraction,
                "healthy": self.healthy_fraction,
            },
            "patch_count": self.patch_count,
            "field_ha": self.field_ha,
            "chosen_option": self.chosen_option,
            "treated_fraction": self.treated_fraction,
            "saving_percent": self.saving_percent,
            "chemical_l": self.chemical_l,
            "saved_l": self.saved_l,
            "status": self.status,
            "map_path": self.map_path,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if include_detail:
            data["detail"] = self.detail_dict()
        return data
