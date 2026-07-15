import os
import secrets

import requests
from flask_jwt_extended import create_access_token

from app.api.models.user import User
from app.api.models.password_reset import PasswordResetOtp
from app.repositories.user_repository import UserRepository
from app.repositories.password_reset_repository import PasswordResetRepository
from app.core.security import hash_password, verify_password
from app.core.mailer import send_otp_email


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

    # ── Password reset (OTP) ─────────────────────────────────────────────────

    @staticmethod
    def forgot_password(email):
        """Issue a 6-digit reset OTP and email it (or return it in dev).

        Responds the same whether or not the email exists, to avoid leaking
        which addresses are registered. Only when the address *is* registered
        and SMTP is unconfigured do we return the code as `debug_otp` so local
        development can proceed without a mail server.
        """
        normalized_email = email.strip().lower()
        generic = {
            "message": "If an account exists for that email, a reset code has "
                       "been sent."
        }

        user = UserRepository.get_by_email(normalized_email)
        if not user:
            # Do not reveal non-existence.
            return generic, 200

        # 6-digit code; hash before storing, keep only the newest per email.
        otp = f"{secrets.randbelow(1_000_000):06d}"
        PasswordResetRepository.invalidate_existing(normalized_email)
        PasswordResetRepository.create(
            email=normalized_email,
            otp_hash=hash_password(otp),
            expires_at=PasswordResetOtp.default_expiry(),
        )

        try:
            sent = send_otp_email(normalized_email, otp)
        except Exception:
            # SMTP is configured but failed — tell the user honestly.
            return {"message": "Could not send the reset email. Try again later."}, 502

        response = dict(generic)
        if not sent:
            # Dev convenience only: no mail server configured.
            response["debug_otp"] = otp
        return response, 200

    @staticmethod
    def reset_password(email, otp, new_password):
        """Verify the OTP and set a new password."""
        normalized_email = email.strip().lower()
        if not new_password or len(new_password) < 6:
            return {"message": "Password must be at least 6 characters."}, 400

        record = PasswordResetRepository.latest_active(normalized_email)
        if record is None or record.is_expired:
            return {"message": "Invalid or expired reset code."}, 400

        if not verify_password(record.otp_hash, str(otp).strip()):
            return {"message": "Invalid or expired reset code."}, 400

        user = UserRepository.get_by_email(normalized_email)
        if not user:
            return {"message": "Invalid or expired reset code."}, 400

        user.password = hash_password(new_password)
        UserRepository.create(user)  # add() on an existing row = update + commit
        PasswordResetRepository.mark_used(record)

        return {"message": "Password has been reset. You can now sign in."}, 200

    # ── Google sign-in ───────────────────────────────────────────────────────

    @staticmethod
    def google_signin(id_token):
        """Verify a Google ID token and sign the user in (creating them if new).

        The token is validated against Google's tokeninfo endpoint; when
        GOOGLE_CLIENT_ID is set we also require the token's audience to match,
        which is what prevents tokens minted for other apps from being accepted.
        """
        if not id_token:
            return {"message": "Missing Google credential."}, 400

        try:
            resp = requests.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": id_token},
                timeout=10,
            )
        except requests.RequestException:
            return {"message": "Could not reach Google to verify sign-in."}, 502

        if resp.status_code != 200:
            return {"message": "Invalid Google credential."}, 401

        info = resp.json()

        client_id = os.environ.get("GOOGLE_CLIENT_ID")
        if client_id and info.get("aud") != client_id:
            return {"message": "Google credential was issued for another app."}, 401

        if str(info.get("email_verified")).lower() != "true":
            return {"message": "Your Google email is not verified."}, 401

        email = (info.get("email") or "").strip().lower()
        if not email:
            return {"message": "Google account has no email."}, 401

        user = UserRepository.get_by_email(email)
        if not user:
            display_name = info.get("name") or email.split("@")[0]
            user = User(
                username=_unique_username(display_name),
                email=email,
                # Google users authenticate via Google; store an unusable
                # random password so the column stays non-null and no one can
                # log in with a guessed password.
                password=hash_password(secrets.token_urlsafe(32)),
            )
            UserRepository.create(user)

        access_token = create_access_token(identity=str(user.id))
        return {"access_token": access_token, "user": user.to_dict()}, 200


def _unique_username(base):
    """Return a username derived from `base` that isn't already taken."""
    candidate = (base or "user").strip()[:100] or "user"
    if not UserRepository.get_by_username(candidate):
        return candidate
    for _ in range(50):
        suffix = secrets.randbelow(10000)
        alt = f"{candidate[:90]}_{suffix}"
        if not UserRepository.get_by_username(alt):
            return alt
    return f"{candidate[:80]}_{secrets.token_hex(4)}"
