"""Service layer for the signed-in user's profile.

Combines the auth `users` row, the optional `user_profiles` extras row, flight
stats derived from mission history, and the paired drone — everything the
Profile screen needs in one payload.
"""

from app.api.models.user import UserProfile
from app.core.database import db
from app.repositories.drone_repository import DroneRepository
from app.repositories.mission_repository import MissionRepository
from app.repositories.user_repository import UserRepository

_EDITABLE_PROFILE_FIELDS = ("role", "organisation", "phone", "location")


class UserService:

    @staticmethod
    def _get_or_create_profile(user_id):
        profile = UserProfile.query.filter_by(user_id=user_id).first()
        if profile is None:
            profile = UserProfile(user_id=user_id)
            db.session.add(profile)
            db.session.commit()
        return profile

    @staticmethod
    def get_me(user_id):
        user = UserRepository.get_by_id(user_id)
        if user is None:
            return {"status": "error", "message": "User not found."}, 404

        profile = UserService._get_or_create_profile(user_id)
        missions_flown, area_ha, air_time_h = MissionRepository.stats_for_user(
            user_id
        )
        drone = DroneRepository.get_by_owner(user_id)

        return {
            "status": "ok",
            "user": {
                **user.to_dict(),
                **profile.to_dict(),
                "stats": {
                    "missions_flown": missions_flown,
                    "area_flown_ha": area_ha,
                    "air_time_hours": air_time_h,
                },
                "drone": drone.to_dict() if drone else None,
            },
        }, 200

    @staticmethod
    def update_me(user_id, payload):
        if not isinstance(payload, dict):
            return {"status": "error", "message": "Request body must be JSON."}, 400

        user = UserRepository.get_by_id(user_id)
        if user is None:
            return {"status": "error", "message": "User not found."}, 404

        username = str(payload.get("username") or "").strip()
        if username and username != user.username:
            existing = UserRepository.get_by_username(username)
            if existing is not None and existing.id != user.id:
                return {"status": "error", "message": "Username already taken."}, 409
            user.username = username

        profile = UserService._get_or_create_profile(user_id)
        for field in _EDITABLE_PROFILE_FIELDS:
            if field in payload:
                value = payload[field]
                setattr(profile, field, str(value).strip() if value else None)

        db.session.commit()
        return UserService.get_me(user_id)
