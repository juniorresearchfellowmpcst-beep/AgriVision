# Import every model so `db.create_all()` (called in app/__init__.py) sees the
# full schema regardless of which routes happen to be imported first.
from app.api.models.user import User, UserProfile
from app.api.models.password_reset import PasswordResetOtp
from app.api.models.drone import Drone
from app.api.models.mission import Mission
from app.api.models.analysis import AnalysisRecord, AlertRecord

__all__ = [
    "User",
    "UserProfile",
    "PasswordResetOtp",
    "Drone",
    "Mission",
    "AnalysisRecord",
    "AlertRecord",
]
