from app.core.database import db

# What a feed is for. "multispectral" frames become vegetation indices and a
# spray prescription; "rgb" frames go to the weed/disease CNN.
CAMERA_ROLES = ("multispectral", "rgb")


class CameraFeed(db.Model):
    """One camera on the aircraft, addressed by URL.

    A multispectral rig is stored as several rows — one per band — because
    that is how the cameras actually present themselves (a stream each), and
    because the band a row carries is what lets a shot be reassembled into the
    ordered stack the index maths needs.
    """

    __tablename__ = "camera_feeds"

    id = db.Column(db.Integer, primary_key=True)

    # Cameras belong to whoever registered them; anonymous rows (NULL) are
    # visible to everyone, matching the drone/mission rule.
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    name = db.Column(db.String(120), nullable=False)

    # multispectral | rgb
    role = db.Column(db.String(20), nullable=False, default="rgb")

    # Which band this sensor sees; only meaningful for role='multispectral'
    # (blue, green, red, red_edge, nir).
    band = db.Column(db.String(20), nullable=True)

    # RTSP / MJPEG / snapshot URL, or a local path when bench testing.
    url = db.Column(db.String(500), nullable=False)

    # Horizontal field of view, needed to turn pixels into metres on the
    # ground when a prescription becomes spray waypoints. Left NULL the
    # prescription still renders, it just cannot be flown.
    fov_deg = db.Column(db.Float, nullable=True)

    enabled = db.Column(db.Boolean, default=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "name": self.name,
            "role": self.role,
            "band": self.band,
            "url": self.url,
            "fov_deg": self.fov_deg,
            "enabled": bool(self.enabled),
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class CaptureFrame(db.Model):
    """One stored still, geotagged with where the aircraft was when it fired.

    Frames are grouped twice over: by ``session_id`` (a flight or field visit)
    and by ``shot_id`` (one trigger of the shutter across every camera). The
    inner grouping is what makes a multispectral shot addressable as a unit —
    five band rows sharing a shot_id are the stack the prescription runs on.
    """

    __tablename__ = "capture_frames"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    camera_id = db.Column(db.Integer, db.ForeignKey("camera_feeds.id"), nullable=True)

    session_id = db.Column(db.String(60), nullable=False, index=True)
    shot_id = db.Column(db.String(60), nullable=False, index=True)

    role = db.Column(db.String(20), nullable=False, default="rgb")
    band = db.Column(db.String(20), nullable=True)

    # Paths relative to the captures root, so moving the deployment (or
    # switching between dev and the server) doesn't orphan every frame.
    path = db.Column(db.String(300), nullable=False)
    preview_path = db.Column(db.String(300), nullable=True)

    width = db.Column(db.Integer, nullable=True)
    height = db.Column(db.Integer, nullable=True)

    # Where the aircraft was. NULL when no vehicle was connected.
    lat = db.Column(db.Float, nullable=True)
    lon = db.Column(db.Float, nullable=True)
    alt_m = db.Column(db.Float, nullable=True)
    heading_deg = db.Column(db.Float, nullable=True)

    field_name = db.Column(db.String(120), nullable=True)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    @property
    def has_fix(self) -> bool:
        return self.lat is not None and self.lon is not None

    def to_dict(self, url_prefix=None):
        data = {
            "id": self.id,
            "session_id": self.session_id,
            "shot_id": self.shot_id,
            "camera_id": self.camera_id,
            "role": self.role,
            "band": self.band,
            "path": self.path,
            "preview_path": self.preview_path,
            "width": self.width,
            "height": self.height,
            "lat": self.lat,
            "lon": self.lon,
            "alt_m": self.alt_m,
            "heading_deg": self.heading_deg,
            "has_fix": self.has_fix,
            "field_name": self.field_name,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if url_prefix:
            prefix = url_prefix.rstrip("/")
            data["url"] = f"{prefix}/{self.path}" if self.path else None
            data["preview_url"] = (
                f"{prefix}/{self.preview_path}" if self.preview_path else None
            )
        return data
