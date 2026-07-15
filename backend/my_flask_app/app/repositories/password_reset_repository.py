"""Data access for password-reset OTP records."""

from app.api.models.password_reset import PasswordResetOtp
from app.core.database import db


class PasswordResetRepository:

    @staticmethod
    def invalidate_existing(email):
        """Delete any outstanding codes for an email before issuing a new one."""
        PasswordResetOtp.query.filter_by(email=email).delete()
        db.session.commit()

    @staticmethod
    def create(email, otp_hash, expires_at):
        record = PasswordResetOtp(
            email=email, otp_hash=otp_hash, expires_at=expires_at
        )
        db.session.add(record)
        db.session.commit()
        return record

    @staticmethod
    def latest_active(email):
        """Most recent unused, unexpired code for an email, or None."""
        return (
            PasswordResetOtp.query.filter_by(email=email, used=False)
            .order_by(PasswordResetOtp.id.desc())
            .first()
        )

    @staticmethod
    def mark_used(record):
        record.used = True
        db.session.commit()
        return record
