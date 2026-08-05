import json

from app.core.database import db


class FieldScanRecord(db.Model):
    """One weed + disease scan of one canopy frame.

    Stored per frame rather than per flight because the useful question later
    is spatial — "where in the block was the rust?" — and that only survives if
    each frame keeps its own verdict and its own coordinates. The flight-level
    summary is derived from these rows, not stored instead of them.
    """

    __tablename__ = "field_scans"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    # Which capture this came from, when it came from one at all (a scan can
    # also be a single photo uploaded from the app).
    session_id = db.Column(db.String(60), nullable=True, index=True)
    shot_id = db.Column(db.String(60), nullable=True, index=True)
    frame_id = db.Column(db.Integer, db.ForeignKey("capture_frames.id"), nullable=True)

    crop = db.Column(db.String(30), nullable=True)

    condition_id = db.Column(db.String(60), nullable=True)
    condition_name = db.Column(db.String(120), nullable=True)
    severity = db.Column(db.String(20), nullable=True)
    confidence = db.Column(db.Float, default=0.0)

    # 'model' when a trained CNN answered, 'heuristic' otherwise. Worth
    # recording: the two are not equally trustworthy, and a season's records
    # are only comparable if you know which produced them.
    engine = db.Column(db.String(20), nullable=True)
    is_healthy = db.Column(db.Boolean, default=False)

    weed_coverage = db.Column(db.Float, default=0.0)
    weed_pressure = db.Column(db.String(20), nullable=True)
    # 'inter-row' | 'appearance' | 'inconclusive' — how the weeds were told
    # apart from the crop, which is what the number's reliability rests on.
    weed_method = db.Column(db.String(20), nullable=True)

    lat = db.Column(db.Float, nullable=True)
    lon = db.Column(db.Float, nullable=True)

    overlay_path = db.Column(db.String(300), nullable=True)
    filename = db.Column(db.String(255), nullable=True)
    field_name = db.Column(db.String(120), nullable=True)

    detail = db.Column(db.Text, nullable=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    def detail_dict(self):
        try:
            return json.loads(self.detail) if self.detail else {}
        except (TypeError, ValueError):
            return {}

    def to_dict(self, include_detail=False, url_prefix=None):
        data = {
            "id": self.id,
            "session_id": self.session_id,
            "shot_id": self.shot_id,
            "frame_id": self.frame_id,
            "crop": self.crop,
            "condition_id": self.condition_id,
            "condition_name": self.condition_name,
            "severity": self.severity,
            "confidence": self.confidence,
            "engine": self.engine,
            "is_healthy": bool(self.is_healthy),
            "weed_coverage": self.weed_coverage,
            "weed_percent": int(round((self.weed_coverage or 0.0) * 100)),
            "weed_pressure": self.weed_pressure,
            "weed_method": self.weed_method,
            "lat": self.lat,
            "lon": self.lon,
            "overlay_path": self.overlay_path,
            "filename": self.filename,
            "field_name": self.field_name,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if url_prefix and self.overlay_path:
            data["overlay_url"] = f"{url_prefix.rstrip('/')}/{self.overlay_path}"
        if include_detail:
            data["detail"] = self.detail_dict()
        return data
