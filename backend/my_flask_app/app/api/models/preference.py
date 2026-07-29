from datetime import datetime

from app.core.database import db

# Every preference the app exposes, with its default. Keeping them in one
# mapping means a new toggle is a single edit here plus a column below, and the
# service can validate incoming keys against it without a second list.
PREFERENCE_DEFAULTS = {
    # Profile screen → NOTIFICATION PREFERENCES
    "mission_updates": True,
    "ai_alerts": True,
    "field_reports": True,
    # Settings screen
    "auto_sync": True,
    "push_notifications": True,
}


class UserPreference(db.Model):
    """Per-user app settings — notification toggles and sync behaviour.

    Stored server-side rather than on the device so a pilot who reinstalls the
    app, or signs in on the spare tablet in the truck, keeps the alerting they
    configured. One row per user; missing rows are created on first read.
    """

    __tablename__ = "user_preferences"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(
        db.Integer, db.ForeignKey("users.id"), unique=True, nullable=False
    )

    # ── notification preferences ──────────────────────────────────────────
    mission_updates = db.Column(db.Boolean, default=True, nullable=False)
    ai_alerts = db.Column(db.Boolean, default=True, nullable=False)
    field_reports = db.Column(db.Boolean, default=True, nullable=False)

    # ── app behaviour ─────────────────────────────────────────────────────
    auto_sync = db.Column(db.Boolean, default=True, nullable=False)
    push_notifications = db.Column(db.Boolean, default=True, nullable=False)

    updated_at = db.Column(db.DateTime, nullable=True)

    def to_dict(self):
        return {key: bool(getattr(self, key)) for key in PREFERENCE_DEFAULTS}

    def apply(self, values: dict):
        """Set any known preference present in ``values``; ignore the rest.

        Returns the keys that actually changed, so the caller can report what
        it did instead of claiming a write that was a no-op.
        """
        changed = []
        for key in PREFERENCE_DEFAULTS:
            if key not in values:
                continue
            new_value = bool(values[key])
            if bool(getattr(self, key)) != new_value:
                setattr(self, key, new_value)
                changed.append(key)
        if changed:
            self.updated_at = datetime.utcnow()
        return changed
