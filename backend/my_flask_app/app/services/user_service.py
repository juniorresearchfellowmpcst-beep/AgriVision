"""Service layer for the signed-in user's profile, preferences and sync state.

Combines the auth `users` row, the optional `user_profiles` extras row, flight
stats derived from mission history, and the paired drone — everything the
Profile screen needs in one payload. Preferences (notification toggles, auto
sync) live here too so they survive a reinstall instead of dying with the
device, and the sync summary tells the Settings screen what the server
actually holds.
"""

from datetime import datetime

from app.api.models.preference import PREFERENCE_DEFAULTS
from app.api.models.user import UserProfile
from app.core.database import db
from app.repositories.analysis_repository import AnalysisRepository
from app.repositories.disease_scan_repository import DiseaseScanRepository
from app.repositories.drone_repository import DroneRepository
from app.repositories.mission_repository import MissionRepository
from app.repositories.preference_repository import PreferenceRepository
from app.repositories.user_repository import UserRepository

_EDITABLE_PROFILE_FIELDS = ("role", "organisation", "phone", "location")

# Mission states the server still considers open — the flight has not been
# closed out, so its log is not final yet.
_OPEN_MISSION_STATES = ("planned", "in_progress")


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

        preferences = PreferenceRepository.get_or_create(user_id)

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
                # Included here so the Profile screen renders its toggles in
                # the same frame as the rest of the profile, with no second
                # request and no flicker from a late-arriving default.
                "preferences": preferences.to_dict(),
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

    # ── Preferences ────────────────────────────────────────────────────────

    @staticmethod
    def get_preferences(user_id):
        if user_id is None:
            return {"status": "error", "message": "Sign in to read settings."}, 401

        preferences = PreferenceRepository.get_or_create(user_id)
        return {
            "status": "ok",
            "preferences": preferences.to_dict(),
            "defaults": dict(PREFERENCE_DEFAULTS),
        }, 200

    @staticmethod
    def update_preferences(user_id, payload):
        """Apply a partial preference update; unknown keys are rejected.

        Rejecting rather than ignoring an unknown key means a typo in the app
        surfaces immediately instead of silently never taking effect.
        """
        if user_id is None:
            return {"status": "error", "message": "Sign in to change settings."}, 401
        if not isinstance(payload, dict):
            return {"status": "error", "message": "Request body must be JSON."}, 400

        unknown = [k for k in payload if k not in PREFERENCE_DEFAULTS]
        if unknown:
            return {
                "status": "error",
                "message": (
                    f"Unknown preference(s): {', '.join(sorted(unknown))}. "
                    f"Valid keys: {', '.join(sorted(PREFERENCE_DEFAULTS))}."
                ),
            }, 400
        if not payload:
            return {"status": "error", "message": "No preferences supplied."}, 400

        preferences = PreferenceRepository.get_or_create(user_id)
        changed = preferences.apply(payload)
        PreferenceRepository.save()

        return {
            "status": "ok",
            "message": (
                f"Updated {', '.join(changed)}." if changed
                else "No change — already set."
            ),
            "changed": changed,
            "preferences": preferences.to_dict(),
        }, 200

    # ── Sync summary ───────────────────────────────────────────────────────

    @staticmethod
    def sync_status(user_id):
        """What the server holds for this user, per record type.

        'pending' counts records the server itself still considers open (a
        flight that was never closed out). Everything else it has stored is
        by definition synced — the server cannot know about records still
        sitting unsent on a device, so this never guesses at those.
        """
        missions = MissionRepository.list_missions(user_id=user_id, limit=1000)
        open_missions = sum(1 for m in missions if m.status in _OPEN_MISSION_STATES)

        reports = AnalysisRepository.list_records(user_id=user_id, limit=1000)
        scans = DiseaseScanRepository.count_for_user(user_id=user_id)

        def entry(key, label, total, pending=0):
            return {
                "key": key,
                "label": label,
                "total": total,
                "pending": pending,
                "status": "pending" if pending else "synced",
            }

        return {
            "status": "ok",
            "checked_at": datetime.utcnow().isoformat(),
            "items": [
                entry("mission_logs", "Mission logs", len(missions), open_missions),
                entry("detection_frames", "Detection frames", scans),
                entry("field_reports", "Field reports", len(reports)),
            ],
        }, 200
