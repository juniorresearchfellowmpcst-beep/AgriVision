"""One survey flight, from camera selection to a sprayed field.

The pieces of this already existed separately -- a camera registry, a live
analyser, a capture session, a spray prescription -- and an operator had to
carry the connection between them in their head: which shot came from which
pass, whether the prescription on screen belongs to the block they just flew,
whether the tank was filled for *this* diagnosis or the last one.

A ``SurveyRun`` is that connection written down. It records what the aircraft
was told to look at (which cameras, which crop, disease or weeds or both),
what it found, and -- separately, and only when a human says so -- that the
tank was filled and spraying was authorised.

The authorisation fields are deliberately not one boolean. "The farmer filled
the tank" and "the farmer agreed to spray" are two different statements, and a
run that opens a valve should be able to show both, with who and when.
"""

import json

from app.core.database import db

# Which cameras the aircraft flies with.
#
#   multispectral — band cameras only. Vegetation indices and a K-means
#                   prescription; no CNN, because a single band is a greyscale
#                   image of one wavelength and not what the model was trained on.
#   rgb           — the ordinary IP camera only. Live CNN disease/weed detection
#                   as it flies, and a prescription clustered from the detections.
#   both          — both rigs. The RGB feed answers *what* is wrong while the
#                   bands answer *where* the field is stressed, and the
#                   prescription is built from the bands with the CNN's
#                   diagnosis attached to it.
CAMERA_MODES = ("multispectral", "rgb", "both")

# What the CNN is asked to look for on this pass.
DETECTION_TARGETS = ("disease", "weed", "both")

# Where the run is. Only 'planned', 'flying' and 'analysed' are reachable
# without a human decision; everything after 'authorised' required one.
SURVEY_STATUSES = (
    "planned",      # camera mode and crop chosen, nothing flown
    "flying",       # analysis running against the live feed
    "analysed",     # the pass is finished and summarised
    "authorised",   # tank confirmed filled and spraying permitted
    "spraying",     # the spray mission is on the aircraft
    "completed",
    "cancelled",
)


class SurveyRun(db.Model):
    """A survey flight and everything decided on the back of it."""

    __tablename__ = "survey_runs"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    # The capture session this run's frames belong to, so a run and the stills
    # taken during it can be brought back together later.
    session_id = db.Column(db.String(60), nullable=False, index=True)

    field_name = db.Column(db.String(120), nullable=True)

    # multispectral | rgb | both
    camera_mode = db.Column(db.String(20), nullable=False, default="rgb")

    # disease | weed | both
    detection_target = db.Column(db.String(20), nullable=False, default="both")

    # Which crop is in the field. Part of the diagnosis, not a label: the same
    # yellowing is yellow rust in wheat and yellow mosaic in soybean.
    crop = db.Column(db.String(40), nullable=True)

    # The RGB camera the live analyser is reading, when there is one.
    rgb_camera_id = db.Column(db.Integer, db.ForeignKey("camera_feeds.id"), nullable=True)

    status = db.Column(db.String(20), nullable=False, default="planned")

    # Rolled-up results, filled in when the pass is finished.
    frames_scanned = db.Column(db.Integer, default=0)
    diseased_frames = db.Column(db.Integer, default=0)
    weed_percent = db.Column(db.Integer, nullable=True)
    health_score = db.Column(db.Integer, nullable=True)      # 0-100
    dominant_condition = db.Column(db.String(120), nullable=True)

    # The prescription built from this run, once there is one.
    prescription_id = db.Column(
        db.Integer, db.ForeignKey("spray_prescriptions.id"), nullable=True
    )

    # -- the human decisions, kept apart from each other -------------------
    tank_filled = db.Column(db.Boolean, default=False)
    tank_litres = db.Column(db.Float, nullable=True)
    tank_product = db.Column(db.String(200), nullable=True)
    spray_authorised = db.Column(db.Boolean, default=False)
    authorised_by = db.Column(db.String(120), nullable=True)
    authorised_at = db.Column(db.DateTime, nullable=True)
    chosen_option = db.Column(db.String(30), nullable=True)

    # The full summary payload (conditions, hotspots, action plan, tank plan),
    # so re-opening a finished run costs a read rather than a re-scan.
    summary = db.Column(db.Text, nullable=True)

    started_at = db.Column(db.DateTime, server_default=db.func.now())
    finished_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, server_default=db.func.now())

    # -- helpers -----------------------------------------------------------

    @property
    def uses_rgb(self) -> bool:
        return self.camera_mode in ("rgb", "both")

    @property
    def uses_multispectral(self) -> bool:
        return self.camera_mode in ("multispectral", "both")

    @property
    def detects_disease(self) -> bool:
        return self.detection_target in ("disease", "both")

    @property
    def detects_weeds(self) -> bool:
        return self.detection_target in ("weed", "both")

    def summary_dict(self):
        try:
            return json.loads(self.summary) if self.summary else {}
        except (TypeError, ValueError):
            return {}

    def to_dict(self, include_summary=False):
        data = {
            "id": self.id,
            "user_id": self.user_id,
            "session_id": self.session_id,
            "field_name": self.field_name,
            "camera_mode": self.camera_mode,
            "detection_target": self.detection_target,
            "crop": self.crop,
            "rgb_camera_id": self.rgb_camera_id,
            "status": self.status,
            "frames_scanned": self.frames_scanned or 0,
            "diseased_frames": self.diseased_frames or 0,
            "weed_percent": self.weed_percent,
            "health_score": self.health_score,
            "dominant_condition": self.dominant_condition,
            "prescription_id": self.prescription_id,
            "tank": {
                "filled": bool(self.tank_filled),
                "litres": self.tank_litres,
                "product": self.tank_product,
            },
            "spray_authorised": bool(self.spray_authorised),
            "authorised_by": self.authorised_by,
            "authorised_at": (
                self.authorised_at.isoformat() if self.authorised_at else None
            ),
            "chosen_option": self.chosen_option,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "finished_at": self.finished_at.isoformat() if self.finished_at else None,
        }
        if include_summary:
            data["summary"] = self.summary_dict()
        return data
