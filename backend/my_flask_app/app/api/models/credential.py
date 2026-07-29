from datetime import date, datetime

from app.core.database import db

# How close to expiry a credential starts warning, in days. A pilot licence
# renewal takes weeks, so warn well before the paperwork actually lapses.
EXPIRING_WINDOW_DAYS = 90

# Credential kinds the app knows how to render an icon for.
CREDENTIAL_KINDS = ("licence", "certification", "clearance", "insurance", "other")


class PilotCredential(db.Model):
    """A licence, certificate or clearance a pilot must hold to fly legally.

    Status is never stored — it is derived from ``expires_on`` every time the
    record is read, so a credential that lapses overnight reports itself as
    expired without anything having to run a job.
    """

    __tablename__ = "pilot_credentials"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)

    # licence | certification | clearance | insurance | other
    kind = db.Column(db.String(20), default="other")

    # Display name, e.g. 'DRONE PILOT LICENCE'.
    label = db.Column(db.String(120), nullable=False)

    # The credential number or scope, e.g. 'DGCA RPA-2024-MH-04871'.
    identifier = db.Column(db.String(160), nullable=True)

    issuer = db.Column(db.String(120), nullable=True)

    issued_on = db.Column(db.Date, nullable=True)

    # Null means the credential does not expire.
    expires_on = db.Column(db.Date, nullable=True)

    notes = db.Column(db.String(255), nullable=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    updated_at = db.Column(db.DateTime, nullable=True)

    def days_until_expiry(self, today=None):
        """Days left before expiry; None when it never expires."""
        if self.expires_on is None:
            return None
        today = today or date.today()
        return (self.expires_on - today).days

    def status(self, today=None):
        """valid | expiring | expired — the badge the Profile screen shows."""
        remaining = self.days_until_expiry(today=today)
        if remaining is None:
            return "valid"
        if remaining < 0:
            return "expired"
        if remaining <= EXPIRING_WINDOW_DAYS:
            return "expiring"
        return "valid"

    def display_value(self, today=None):
        """What to show as the row's value.

        The identifier when there is one; otherwise a plain-language expiry so
        an insurance policy row still says something useful.
        """
        if self.identifier:
            return self.identifier
        if self.expires_on:
            verb = "Expired" if self.status(today) == "expired" else "Expires"
            return f"{verb} {self.expires_on.strftime('%b %Y')}"
        return "—"

    def to_dict(self, today=None):
        return {
            "id": self.id,
            "kind": self.kind,
            "label": self.label,
            "identifier": self.identifier,
            "issuer": self.issuer,
            "issued_on": self.issued_on.isoformat() if self.issued_on else None,
            "expires_on": self.expires_on.isoformat() if self.expires_on else None,
            "notes": self.notes,
            "status": self.status(today),
            "days_until_expiry": self.days_until_expiry(today),
            "value": self.display_value(today),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

    def touch(self):
        self.updated_at = datetime.utcnow()
