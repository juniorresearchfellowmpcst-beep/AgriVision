"""Password-reset OTP records.

One row per issued reset code. The OTP itself is never stored in the clear —
only its bcrypt hash — and every row carries a short expiry. `create_all`
provisions the table automatically at app start.
"""

from datetime import datetime, timedelta

from app.core.database import db

# How long a reset code stays valid.
OTP_TTL_MINUTES = 10


class PasswordResetOtp(db.Model):
    __tablename__ = "password_reset_otps"

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), nullable=False, index=True)
    otp_hash = db.Column(db.String(255), nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    used = db.Column(db.Boolean, nullable=False, default=False)
    created_at = db.Column(db.DateTime, server_default=db.func.now())

    @staticmethod
    def default_expiry() -> datetime:
        return datetime.utcnow() + timedelta(minutes=OTP_TTL_MINUTES)

    @property
    def is_expired(self) -> bool:
        return datetime.utcnow() > self.expires_at
