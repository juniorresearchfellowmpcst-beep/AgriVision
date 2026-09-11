"""Deleting an account, and everything the account owns.

Google Play's User Data policy requires an app that lets people create an
account to let them delete it -- from inside the app, and from a web page for
someone who has already uninstalled it. "Delete" there means the account *and
its data*, not a flag on a row, so this removes every record that belongs to
the user and the image files those records point at.

Two things make it more than a list of deletes.

**Order.** Several tables point at each other: a field scan at a capture
frame, a survey run at a camera and at a prescription. On PostgreSQL a parent
row cannot be deleted while a child still references it, so children go
first -- and any *other* user's row that happens to reference something being
deleted is detached (its foreign key set to NULL) rather than blocking the
deletion or being deleted along with it.

**Files.** Photos and overlays live on disk under the app's instance folder.
They are removed only after the database commit, so a failed commit never
leaves rows pointing at files that are gone. And only ever *inside* that
folder: a stored path that resolves anywhere else is ignored, whatever it
says, so no row can be used to delete a file the app does not own.
"""

from __future__ import annotations

import logging
import os
import shutil
from typing import Any, Dict, Iterable, List, Tuple

from app.api.models.advisor_report import AdvisorReport
from app.api.models.analysis import AlertRecord, AnalysisRecord
from app.api.models.capture import CameraFeed, CaptureFrame
from app.api.models.credential import PilotCredential
from app.api.models.disease_scan import DiseaseScan
from app.api.models.drone import Drone
from app.api.models.field_scan import FieldScanRecord
from app.api.models.mission import Mission
from app.api.models.password_reset import PasswordResetOtp
from app.api.models.preference import UserPreference
from app.api.models.spray import SprayPrescription
from app.api.models.survey import SurveyRun
from app.api.models.user import User, UserProfile
from app.core.database import db

logger = logging.getLogger(__name__)

# Every folder under the instance path that holds per-user files. One list, so
# a new feature that stores files has exactly one place to register itself.
STORAGE_SUBDIRS = (
    "captures",
    "analysis_outputs",
    "fieldscan_outputs",
    "spray_outputs",
    "fieldscan",
    "spray",
)

# Deleted in this order: every table here is a child of the ones after it.
_OWNED = (
    (AnalysisRecord, "user_id"),
    (SurveyRun, "user_id"),
    (FieldScanRecord, "user_id"),
    (SprayPrescription, "user_id"),
    (CaptureFrame, "user_id"),
    (CameraFeed, "user_id"),
    (DiseaseScan, "user_id"),
    (Mission, "user_id"),
    (Drone, "owner_id"),
    (PilotCredential, "user_id"),
    (UserPreference, "user_id"),
    (UserProfile, "user_id"),
    (AdvisorReport, "user_id"),
)


class AccountService:

    @staticmethod
    def delete_account(
        user_id, confirm_email, instance_path
    ) -> Tuple[Dict[str, Any], int]:
        """Delete the account, its rows and its files.

        ``confirm_email`` must match the account's email address. It is what
        stands between one mistaken tap and a farmer's whole history.
        """
        user = db.session.get(User, user_id) if user_id is not None else None
        if user is None:
            return {"message": "Account not found."}, 404

        typed = (confirm_email or "").strip().lower()
        if not typed or typed != (user.email or "").strip().lower():
            return {
                "message": "Type your account's email address exactly to confirm."
            }, 400

        try:
            paths, session_ids = AccountService._purge_rows(user)
            db.session.commit()
        except Exception:
            db.session.rollback()
            logger.exception("Account %s could not be deleted", user_id)
            return {
                "message": "The account could not be deleted. Nothing was "
                           "removed -- try again, or contact support."
            }, 500

        removed = AccountService._remove_files(paths, session_ids, instance_path)
        logger.info("Account %s deleted; %s file(s) removed", user_id, removed)
        return {
            "message": "Your account and all of its data have been deleted.",
            "files_removed": removed,
        }, 200

    # ── rows ──────────────────────────────────────────────────────────────

    @staticmethod
    def _purge_rows(user: User) -> Tuple[List[str], List[str]]:
        """Delete every row the user owns. Returns the files to remove after."""
        uid = user.id

        frames = CaptureFrame.query.filter_by(user_id=uid).all()
        scans = FieldScanRecord.query.filter_by(user_id=uid).all()
        prescriptions = SprayPrescription.query.filter_by(user_id=uid).all()
        runs = SurveyRun.query.filter_by(user_id=uid).all()
        cameras = CameraFeed.query.filter_by(user_id=uid).all()
        analyses = AnalysisRecord.query.filter_by(user_id=uid).all()

        frame_ids = [row.id for row in frames]
        camera_ids = [row.id for row in cameras]
        prescription_ids = [row.id for row in prescriptions]
        analysis_ids = [row.id for row in analyses]

        paths = [p for f in frames for p in (f.path, f.preview_path) if p]
        paths += [s.overlay_path for s in scans if s.overlay_path]
        paths += [p.map_path for p in prescriptions if p.map_path]
        session_ids = [r.session_id for r in runs if r.session_id]

        # Detach everything that points at what is about to go -- including
        # rows that belong to someone else. They keep their own data, minus a
        # pointer at this user's.
        if frame_ids:
            FieldScanRecord.query.filter(
                FieldScanRecord.frame_id.in_(frame_ids)
            ).update({"frame_id": None}, synchronize_session=False)
        if camera_ids:
            CaptureFrame.query.filter(
                CaptureFrame.camera_id.in_(camera_ids)
            ).update({"camera_id": None}, synchronize_session=False)
            SurveyRun.query.filter(
                SurveyRun.rgb_camera_id.in_(camera_ids)
            ).update({"rgb_camera_id": None}, synchronize_session=False)
        if prescription_ids:
            SurveyRun.query.filter(
                SurveyRun.prescription_id.in_(prescription_ids)
            ).update({"prescription_id": None}, synchronize_session=False)
        if analysis_ids:
            # An alert has no meaning without its analysis; it goes with it.
            AlertRecord.query.filter(
                AlertRecord.analysis_id.in_(analysis_ids)
            ).delete(synchronize_session=False)

        for model, column in _OWNED:
            model.query.filter(getattr(model, column) == uid).delete(
                synchronize_session=False
            )

        email = (user.email or "").strip().lower()
        if email:
            PasswordResetOtp.query.filter_by(email=email).delete(
                synchronize_session=False
            )

        db.session.delete(user)
        return paths, session_ids

    # ── files ─────────────────────────────────────────────────────────────

    @staticmethod
    def _remove_files(
        paths: Iterable[str], session_ids: Iterable[str], instance_path
    ) -> int:
        """Remove stored files, never touching anything outside the instance."""
        if not instance_path:
            return 0
        root = os.path.normcase(os.path.realpath(instance_path))

        def inside(candidate: str) -> bool:
            real = os.path.normcase(os.path.realpath(candidate))
            return real != root and real.startswith(root + os.sep)

        # A stored path may be absolute, relative to the instance folder, or
        # relative to one of its storage folders. Try each reading; the
        # `inside` check below is what makes that safe.
        candidates = set()
        for stored in paths:
            if os.path.isabs(stored):
                candidates.add(stored)
                continue
            candidates.add(os.path.join(instance_path, stored))
            for sub in STORAGE_SUBDIRS:
                candidates.add(os.path.join(instance_path, sub, stored))

        removed = 0
        for candidate in candidates:
            try:
                if inside(candidate) and os.path.isfile(candidate):
                    os.remove(candidate)
                    removed += 1
            except OSError as exc:
                logger.warning("Could not remove %s: %s", candidate, exc)

        for session_id in session_ids:
            # A session id names a folder. Anything that could climb out of
            # one is not a session id, whatever the database says.
            if not session_id or any(s in session_id for s in ("/", "\\", "..")):
                continue
            for sub in STORAGE_SUBDIRS:
                folder = os.path.join(instance_path, sub, session_id)
                if inside(folder) and os.path.isdir(folder):
                    shutil.rmtree(folder, ignore_errors=True)
                    removed += 1
        return removed
