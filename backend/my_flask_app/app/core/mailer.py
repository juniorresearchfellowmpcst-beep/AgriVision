"""Minimal SMTP e-mail sender for transactional mail (password-reset OTPs).

Configured entirely via environment variables so no secrets live in code:

    MAIL_SERVER    e.g. smtp.gmail.com
    MAIL_PORT      e.g. 587           (defaults to 587, STARTTLS)
    MAIL_USERNAME  SMTP login / from address
    MAIL_PASSWORD  SMTP password or app-password
    MAIL_SENDER    optional From address (defaults to MAIL_USERNAME)

When SMTP is **not** configured, `send_otp_email` returns False instead of
raising, so the caller can fall back to returning the OTP in the API response
for local development (see AuthService.forgot_password).
"""

import os
import smtplib
from email.message import EmailMessage


def mail_configured() -> bool:
    """True only when the minimum SMTP settings are present in the environment."""
    return all(
        os.environ.get(k)
        for k in ("MAIL_SERVER", "MAIL_USERNAME", "MAIL_PASSWORD")
    )


def send_otp_email(to_email: str, otp: str) -> bool:
    """Send a password-reset OTP. Returns True if sent, False if not configured.

    Raises only on an actual SMTP failure when mail *is* configured, so the
    caller can surface a real "could not send" error to the user.
    """
    if not mail_configured():
        return False

    server = os.environ["MAIL_SERVER"]
    port = int(os.environ.get("MAIL_PORT", 587))
    username = os.environ["MAIL_USERNAME"]
    password = os.environ["MAIL_PASSWORD"]
    sender = os.environ.get("MAIL_SENDER", username)

    msg = EmailMessage()
    msg["Subject"] = "Your AgriVision password reset code"
    msg["From"] = sender
    msg["To"] = to_email
    msg.set_content(
        f"Your AgriVision password reset code is: {otp}\n\n"
        "It expires in 10 minutes. If you did not request this, ignore this email."
    )

    with smtplib.SMTP(server, port, timeout=15) as smtp:
        smtp.starttls()
        smtp.login(username, password)
        smtp.send_message(msg)
    return True
