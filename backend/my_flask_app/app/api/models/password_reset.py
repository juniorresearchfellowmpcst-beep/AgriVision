from app.core.database import db


class PasswordResetOtp(db.Model):
    __tablename__ = 'password_reset_otps'

    id = db.Column(db.Integer, primary_key=True)

    email = db.Column(db.String(120), nullable=False, index=True)

    otp_hash = db.Column(db.String(255), nullable=False)

    expires_at = db.Column(db.DateTime, nullable=False)

    used = db.Column(db.Boolean, nullable=False, default=False)

    created_at = db.Column(db.DateTime, server_default=db.func.now())
