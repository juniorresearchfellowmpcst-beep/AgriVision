import secrets
from datetime import datetime, timedelta

from flask_jwt_extended import create_access_token
from app.api.models.user import User
from app.api.models.password_reset import PasswordResetOtp
from app.core.database import db
from app.core.mailer import send_otp_email
from app.repositories.user_repository import UserRepository
from app.core.security import hash_password, verify_password

OTP_VALIDITY = timedelta(minutes=10)


class AuthService:
    @staticmethod
    def signup(name, email, password):
        normalized_email = email.strip().lower()
        user = UserRepository.get_by_email(normalized_email)

        if user:
            return {"message": "Email already exists"}, 409

        new_user = User(
            username=name.strip(),
            email=normalized_email,
            password=hash_password(password),
        )

        UserRepository.create(new_user)

        return {"message": "User Registered Successfully"}, 201

    @staticmethod
    def signin(email, password):
        normalized_email = email.strip().lower()
        user = UserRepository.get_by_email(normalized_email)

        if not user:
            return {"message": "Invalid email or password"}, 401

        if not verify_password(user.password, password):
            return {"message": "Invalid email or password"}, 401

        access_token = create_access_token(identity=str(user.id))

        return {
            "access_token": access_token,
            "user": user.to_dict(),
        }, 200

    @staticmethod
    def forgot_password(email):
        normalized_email = email.strip().lower()
        user = UserRepository.get_by_email(normalized_email)

        if not user:
            return {"message": "No account found with this email"}, 404

        # A fresh OTP invalidates any earlier one still pending for this email.
        PasswordResetOtp.query.filter_by(email=normalized_email, used=False).update(
            {"used": True}
        )

        otp = f"{secrets.randbelow(1_000_000):06d}"

        db.session.add(
            PasswordResetOtp(
                email=normalized_email,
                otp_hash=hash_password(otp),
                expires_at=datetime.utcnow() + OTP_VALIDITY,
            )
        )
        db.session.commit()

        emailed = send_otp_email(normalized_email, otp)

        response = {"message": "OTP sent to your email"}
        if not emailed:
            # SMTP is not configured (development build): hand the OTP back
            # so the reset flow stays usable without a mail server.
            response["message"] = "OTP generated (email not configured)"
            response["debug_otp"] = otp

        return response, 200

    @staticmethod
    def reset_password(email, otp, new_password):
        normalized_email = email.strip().lower()
        user = UserRepository.get_by_email(normalized_email)

        if not user:
            return {"message": "No account found with this email"}, 404

        if len(new_password) < 6:
            return {"message": "Password must be at least 6 characters"}, 400

        record = (
            PasswordResetOtp.query.filter_by(email=normalized_email, used=False)
            .order_by(PasswordResetOtp.id.desc())
            .first()
        )

        if not record or datetime.utcnow() > record.expires_at:
            return {"message": "OTP expired. Please request a new one"}, 400

        if not verify_password(record.otp_hash, otp):
            return {"message": "Invalid OTP"}, 400

        record.used = True
        user.password = hash_password(new_password)
        db.session.commit()

        return {"message": "Password reset successfully"}, 200