import os
import smtplib
from email.message import EmailMessage


def is_mail_configured():
    return bool(os.environ.get("MAIL_USERNAME") and os.environ.get("MAIL_PASSWORD"))


def send_otp_email(recipient, otp):
    """Send the password-reset OTP via SMTP.

    Reads MAIL_SERVER / MAIL_PORT / MAIL_USERNAME / MAIL_PASSWORD from the
    environment (defaults to Gmail SMTP). Returns True when the email was
    sent, False when mail is not configured or sending failed — callers fall
    back to returning the OTP in the API response for development builds.
    """
    if not is_mail_configured():
        return False

    server = os.environ.get("MAIL_SERVER", "smtp.gmail.com")
    port = int(os.environ.get("MAIL_PORT", "587"))
    username = os.environ["MAIL_USERNAME"]
    password = os.environ["MAIL_PASSWORD"]

    message = EmailMessage()
    message["Subject"] = "AgriVision password reset code"
    message["From"] = os.environ.get("MAIL_SENDER", username)
    message["To"] = recipient
    message.set_content(
        "Your AgriVision password reset code is: "
        f"{otp}\n\n"
        "The code expires in 10 minutes. If you did not request a password "
        "reset, you can ignore this email."
    )

    try:
        with smtplib.SMTP(server, port, timeout=15) as smtp:
            smtp.starttls()
            smtp.login(username, password)
            smtp.send_message(message)
        return True
    except (smtplib.SMTPException, OSError):
        return False
