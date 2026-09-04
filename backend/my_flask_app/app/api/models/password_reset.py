"""Password-reset OTP records.

One row per issued reset code. The OTP itself is never stored in the clear —
only its bcrypt hash — and every row carries a short expiry. `create_all`
provisions the table automatically at app start.
"""

from datetime import datetime, timedelta

from app.core.database import db

# How long a reset code stays valid.
OTP_TTL_MINUTES = 10

# How many wrong guesses one code tolerates before it is burned.
#
# The route's rate limiter counts requests per caller address, which stops one
# machine hammering the endpoint but not several doing a share each. The search
# space is only a million codes, so the guess budget has to be tied to the
# *code* rather than to whoever is asking. Five is enough for a mistyped digit
# and nowhere near enough to search.
MAX_OTP_ATTEMPTS = 5


class PasswordResetOtp(db.Model):
    __tablename__ = "password_reset_otps"

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), nullable=False, index=True)
    otp_hash = db.Column(db.String(255), nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    used = db.Column(db.Boolean, nullable=False, default=False)
    attempts = db.Column(db.Integer, nullable=False, default=0, server_default="0")
    created_at = db.Column(db.DateTime, server_default=db.func.now())

    @staticmethod
    def default_expiry() -> datetime:
        return datetime.utcnow() + timedelta(minutes=OTP_TTL_MINUTES)

    @property
    def is_expired(self) -> bool:
        return datetime.utcnow() > self.expires_at

    @property
    def is_exhausted(self) -> bool:
        """Too many wrong guesses. Spent, the same as used or expired."""
        return (self.attempts or 0) >= MAX_OTP_ATTEMPTS
