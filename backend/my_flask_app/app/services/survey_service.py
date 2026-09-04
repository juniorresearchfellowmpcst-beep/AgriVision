"""The survey flight, end to end.

Everything this orchestrates already existed. What did not exist was the thread
running through it, and the absence showed up as work the operator had to do in
their head between four screens: pick the cameras, remember which shot came
from which pass, run the scan, read the numbers, decide what to buy, fill the
tank, find the prescription again, and only then authorise a spray.

A survey run is that thread:

    choose cameras + crop + what to look for
        -> fly; the RGB feed is scanned by the CNN as the aircraft moves
        -> finish; every frame of the pass is rolled into one crop-health
           answer, an action plan, and a tank plan naming actual products
        -> K-means over what was found becomes the treatment map
        -> the farmer fills the tank and gives permission -- two separate
           statements, both recorded
        -> the aircraft flies the map and sprays only the affected areas

The camera mode is the branch that shapes the whole run:

    ``rgb``           the ordinary IP camera. The CNN runs live on the video
                      feed; the map is K-means over the geotagged detections
                      (:mod:`app.spray.hotspot_zones`).
    ``multispectral`` band cameras. No CNN -- a single band is a greyscale
                      image of one wavelength, not what the model was trained
                      on. The map is K-means over a vegetation index
                      (:mod:`app.spray.prescription`), which is the more
                      accurate of the two.
    ``both``          both rigs. The CNN says *what* is wrong, the bands say
                      *where* the field is stressed, and the prescription is
                      built from the bands with the diagnosis attached. This is
                      the mode the feature is really for; the other two exist
                      because most rigs only carry one of the cameras.

Nothing here opens a valve on its own. :meth:`SurveyService.authorise` is the
only path to a spray, it requires an explicit tank confirmation *and* an
explicit permission, and it refuses both if the run never found anything worth
spraying.
"""

from __future__ import annotations

import logging
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from app.ai import field_scan, treatment_kb
from app.ai.crop_kb import get_crop
from app.ai.gemini_advisor import capabilities as advisor_capabilities
from app.api.models.survey import CAMERA_MODES, DETECTION_TARGETS, SurveyRun
from app.repositories.capture_repository import CameraRepository, CaptureFrameRepository
from app.repositories.spray_repository import SprayRepository
from app.repositories.survey_repository import SurveyRepository
from app.services.capture_service import CaptureService
from app.services.live_analysis import LiveAnalysisService
from app.services.spray_service import SprayService
from app.spray import spray_config
from app.spray.hotspot_zones import HotspotError, cluster_detections, hotspot_geojson

logger = logging.getLogger(__name__)

# How often the live analyser samples the feed during a survey. Slower than the
# module default: a survey pass is minutes long, and the aircraft needs several
# seconds to clear its own frame width, so faster sampling mostly re-scans the
# same ground at the cost of the flight controller's CPU.
SURVEY_INTERVAL_S = 3.0

# Below this many scanned frames a "field health summary" is not a summary of a
# field, it is a summary of a few seconds of hovering. The run still finishes --
# refusing to show what was found would be worse -- but the answer is labelled.
MIN_FRAMES_FOR_CONFIDENCE = 8


def _fail(message: str, status: int = 400) -> Tuple[Dict[str, Any], int]:
    return {"status": "error", "message": message}, status


def _new_session_id() -> str:
    return f"survey_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{int(time.time() * 1000) % 10000:04d}"


class SurveyService:
    """Start, watch, summarise and act on a survey flight."""

    # -- capabilities ------------------------------------------------------

    @staticmethod
    def capabilities(user_id: Optional[int] = None) -> Tuple[Dict[str, Any], int]:
        """Which camera modes this rig can actually fly, and why not otherwise.

        The app disables a mode rather than letting the operator choose one and
        discover at 30 metres that no camera is registered for it.
        """
        cameras = CameraRepository.list_cameras(user_id=user_id)
        rgb = [c for c in cameras if c.role == "rgb" and c.enabled]
        bands = [c for c in cameras if c.role == "multispectral" and c.enabled]
        band_names = sorted({c.band for c in bands if c.band})

        # Any index worth clustering needs a red + NIR pair. Registering three
        # green cameras is not a multispectral rig.
        has_index_pair = {"red", "nir"}.issubset(set(band_names))

        modes = [
            {
                "id": "rgb",
                "name": "IP camera",
                "detail": "Live CNN disease and weed detection from the video "
                          "feed as the aircraft flies.",
                "available": bool(rgb),
                "reason": "" if rgb else
                          "No RGB camera is registered. Add one on the Drone "
                          "Capture screen.",
                "cameras": [c.to_dict() for c in rgb],
            },
            {
                "id": "multispectral",
                "name": "Multispectral",
                "detail": "Vegetation indices and a K-means zone map. More "
                          "accurate about where the field is stressed, and "
                          "silent about which disease it is.",
                "available": has_index_pair,
                "reason": "" if has_index_pair else (
                    "A red and an NIR band camera are both needed to compute a "
                    f"vegetation index (registered: {', '.join(band_names) or 'none'})."
                ),
                "cameras": [c.to_dict() for c in bands],
            },
            {
                "id": "both",
                "name": "Both",
                "detail": "The CNN names the disease from the RGB feed while "
                          "the bands map where the field is worst. The "
                          "prescription is built from the bands.",
                "available": bool(rgb) and has_index_pair,
                "reason": "" if (rgb and has_index_pair) else
                          "Needs an RGB camera and a red + NIR band pair.",
                "cameras": [c.to_dict() for c in rgb + bands],
            },
        ]

        return {
            "status": "ok",
            "camera_modes": modes,
            "detection_targets": [
                {"id": "disease", "name": "Disease only",
                 "detail": "Runs the crop-disease CNN and skips weed detection."},
                {"id": "weed", "name": "Weed only",
                 "detail": "Runs weed detection and skips the disease CNN — "
                           "about twice as fast per frame."},
                {"id": "both", "name": "Disease + weeds",
                 "detail": "Both detectors on every sampled frame."},
            ],
            "advisor": advisor_capabilities(),
            "spray_hardware": spray_config(),
            "interval_s": SURVEY_INTERVAL_S,
            "flight_link": SurveyService._flight_link(),
        }, 200

    @staticmethod
    def _flight_link() -> Dict[str, Any]:
        """Whether a vehicle is on the link, and what its absence costs.

        Reported so the app can *say* what this survey will produce instead of
        letting the operator find out afterwards. The distinction matters and
        is easy to state wrongly in either direction:

        detection needs no drone at all -- the CNN reads pixels off whatever
        the camera sends, so a bench camera on a workshop table gives a real
        diagnosis. What the flight link buys is position. Without it the
        frames have no coordinates, so there is no K-means hotspot map and
        nothing to fly a spray mission against.

        So: never block the survey on this, and never imply a spray plan is
        coming when it is not.
        """
        try:
            from app.mavlink.link import link

            snapshot = link.snapshot()
            connected = bool(snapshot.get("connected"))
            fix = (snapshot.get("telemetry") or {}).get("gps_fix")
        except Exception:
            # The link module is optional at import time on a ground station
            # with no pymavlink. That is a reason to say "no link", not to
            # fail the whole capabilities call and take the screen down.
            connected, fix = False, None

        # 3D fix or better. Below that the position is not worth building a
        # spray map from, even though a heartbeat is present.
        located = bool(connected and fix is not None and int(fix) >= 3)

        return {
            "connected": connected,
            "gps_fix": fix,
            "can_map": located,
            "detail": (
                "Flight link up with a GPS fix. Detections will be mapped and "
                "a spray plan can be built."
                if located
                else "Flight link up, waiting for a GPS fix. Detection works "
                     "now; the spray map needs position."
                if connected
                else "No flight link. Detection still works from the camera "
                     "alone — you will get a diagnosis, but no field map and "
                     "no spray plan until the drone is connected."
            ),
        }

    # -- start -------------------------------------------------------------

    @staticmethod
    def start(
        payload: Optional[Dict], user_id: Optional[int] = None
    ) -> Tuple[Dict[str, Any], int]:
        """Begin a survey run and, for the RGB modes, start scanning the feed.

        Payload: ``{"camera_mode": "both", "crop": "soybean",
        "detection_target": "both", "field_name": "Block A",
        "rgb_camera_id": 1}``
        """
        payload = payload if isinstance(payload, dict) else {}

        camera_mode = str(payload.get("camera_mode") or "rgb").strip().lower()
        if camera_mode not in CAMERA_MODES:
            return _fail(
                f"camera_mode must be one of: {', '.join(CAMERA_MODES)}."
            )

        target = str(payload.get("detection_target") or "both").strip().lower()
        if target not in DETECTION_TARGETS:
            return _fail(
                f"detection_target must be one of: {', '.join(DETECTION_TARGETS)}."
            )

        crop = payload.get("crop") or None
        if crop and not get_crop(crop):
            return _fail(f"Unknown crop '{crop}'.")

        capability, _status = SurveyService.capabilities(user_id=user_id)
        mode = next(
            (m for m in capability["camera_modes"] if m["id"] == camera_mode), None
        )
        if mode and not mode["available"]:
            return _fail(mode["reason"] or f"{mode['name']} is not available.", 409)

        # A run already in the air is a run this one would fight with: two
        # analysers on one camera, two prescriptions for one tank.
        existing = SurveyRepository.active_for(user_id)
        if existing is not None and existing.status == "flying":
            return _fail(
                f"Survey #{existing.id} is still flying. Finish it before "
                "starting another — there is one aircraft.",
                409,
            )

        run = SurveyRun(
            user_id=user_id,
            session_id=str(payload.get("session_id") or "").strip() or _new_session_id(),
            field_name=payload.get("field_name") or None,
            camera_mode=camera_mode,
            detection_target=target,
            crop=crop,
            status="planned",
        )

        warnings: List[str] = []

        if run.uses_rgb:
            camera, error = SurveyService._rgb_camera(payload, user_id)
            if error:
                return error
            run.rgb_camera_id = camera.id

            started, status = LiveAnalysisService.start(
                {
                    "crop": crop,
                    "interval_s": payload.get("interval_s") or SURVEY_INTERVAL_S,
                    "window": payload.get("window") or 60,
                    "field_name": run.field_name,
                    "target": target,
                },
                camera,
            )
            if status != 200:
                # The feed could not be opened. Say so now, on the ground,
                # rather than producing an empty summary after the flight.
                return started, status
            run.status = "flying"
        else:
            # Multispectral-only: nothing streams, the operator triggers shots.
            run.status = "flying"
            warnings.append(
                "Multispectral-only survey: there is no live disease readout, "
                "because a single band is a greyscale image of one wavelength "
                "and not what the CNN was trained on. Trigger a shot over each "
                "part of the block; the zone map is built when you finish."
            )

        SurveyRepository.create(run)

        return {
            "status": "ok",
            "message": f"Survey #{run.id} started over "
                       f"{run.field_name or 'the block'}.",
            "run": run.to_dict(),
            "warnings": warnings,
        }, 200

    @staticmethod
    def _rgb_camera(payload: Dict, user_id: Optional[int]):
        """The RGB feed this run reads, chosen or inferred."""
        camera_id = payload.get("rgb_camera_id")
        if camera_id not in (None, ""):
            camera, error = CaptureService.resolve_camera(camera_id, user_id)
            if error:
                return None, error
            if camera.role != "rgb":
                return None, _fail(
                    f"{camera.name} is a {camera.role} camera. Live scanning "
                    "reads the ordinary RGB feed.",
                    409,
                )
            return camera, None

        cameras = [
            c for c in CameraRepository.list_cameras(user_id=user_id)
            if c.role == "rgb" and c.enabled
        ]
        if not cameras:
            return None, _fail(
                "No RGB camera is registered, so there is no video feed to "
                "scan. Add one on the Drone Capture screen, or fly a "
                "multispectral-only survey.",
                409,
            )
        return cameras[0], None

    # -- while it flies ----------------------------------------------------

    @staticmethod
    def status(
        run_id: int, user_id: Optional[int] = None
    ) -> Tuple[Dict[str, Any], int]:
        """What the run has found so far, for the in-flight screen."""
        run, error = SurveyService._owned(run_id, user_id)
        if error:
            return error

        payload: Dict[str, Any] = {
            "status": "ok",
            "run": run.to_dict(include_summary=run.status != "flying"),
        }

        if run.uses_rgb and run.rgb_camera_id is not None:
            analysis, _status = LiveAnalysisService.status(str(run.rgb_camera_id))
            payload["analysis"] = analysis.get("analysis")

        if run.uses_multispectral:
            shots = CaptureFrameRepository.list_frames(
                user_id=user_id, session_id=run.session_id, limit=200
            )
            payload["shots"] = len(
                {f.shot_id for f in shots if f.role == "multispectral"}
            )
            payload["frames_captured"] = len(shots)

        return payload, 200

    @staticmethod
    def shoot(
        run_id: int,
        base_dir: str,
        url_prefix: str,
        payload: Optional[Dict] = None,
        user_id: Optional[int] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Trigger every camera once, filed under this run's session.

        The session id is taken from the run rather than the request, which is
        the whole point of having a run: a shot fired during a survey belongs
        to that survey and cannot be filed against the wrong one by a stale
        screen.
        """
        run, error = SurveyService._owned(run_id, user_id)
        if error:
            return error
        if run.status not in ("planned", "flying"):
            return _fail(
                f"Survey #{run.id} has already been {run.status}. Start a new "
                "one to capture more.",
                409,
            )

        payload = payload if isinstance(payload, dict) else {}
        return CaptureService.shoot(
            base_dir=base_dir,
            session_id=run.session_id,
            camera_ids=payload.get("camera_ids"),
            field_name=run.field_name,
            user_id=user_id,
            url_prefix=url_prefix,
        )

    # -- finish ------------------------------------------------------------

    @staticmethod
    def finish(
        run_id: int,
        capture_base: str,
        output_base: str,
        url_prefix: str,
        payload: Optional[Dict] = None,
        user_id: Optional[int] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """End the pass and produce the summary the operator acts on.

        Three things come out of this, in order of how much they cost:
        the crop-health answer over every frame of the pass, the action plan
        and tank plan derived from it, and the K-means treatment map that a
        spray run would follow.
        """
        run, error = SurveyService._owned(run_id, user_id)
        if error:
            return error
        if run.status in ("analysed", "authorised", "spraying", "completed"):
            # Finishing twice is a double-tap on a slow connection, not a new
            # intention. Hand back what was already computed.
            return SurveyService.summary(run_id, user_id=user_id)
        if run.status == "cancelled":
            return _fail(f"Survey #{run.id} was cancelled.", 409)

        payload = payload if isinstance(payload, dict) else {}

        scans: List[Dict[str, Any]] = []
        notes: List[str] = []

        if run.uses_rgb and run.rgb_camera_id is not None:
            scans = LiveAnalysisService.history(str(run.rgb_camera_id))
            # Stop the analyser only *after* its history has been read: the
            # samples live on the analyser object, and stopping first would
            # race the reader against the manager dropping it.
            LiveAnalysisService.stop(str(run.rgb_camera_id))
            if not scans:
                notes.append(
                    "The live scan produced no usable frames. Check that the "
                    "camera stayed connected for the pass."
                )

        summary = (
            field_scan.aggregate(scans, crop=run.crop)
            if scans
            else {"status": "empty", "frames": 0}
        )

        health = SurveyService._health(summary, run)
        conditions = summary.get("conditions") or []
        weed_level = ((summary.get("weed") or {}).get("level")) if scans else None

        tank_plan = treatment_kb.spray_plan(
            conditions=[c for c in conditions if c.get("id") != "healthy"],
            crop_id=run.crop,
            weed_pressure=weed_level if run.detects_weeds else None,
        )

        treatments = [
            {
                "condition": condition.get("name"),
                "condition_id": condition.get("id"),
                "frame_share": condition.get("frame_share"),
                "worst_severity": condition.get("worst_severity"),
                **treatment_kb.treatment_for(condition.get("id")),
            }
            for condition in conditions
            if condition.get("id") != "healthy"
        ]

        prescription, prescription_note = SurveyService._build_map(
            run=run,
            scans=scans,
            payload=payload,
            capture_base=capture_base,
            output_base=output_base,
            url_prefix=url_prefix,
            user_id=user_id,
        )
        if prescription_note:
            notes.append(prescription_note)

        if len(scans) and len(scans) < MIN_FRAMES_FOR_CONFIDENCE:
            notes.append(
                f"Only {len(scans)} frame(s) were scanned. That is a spot "
                "check, not a survey of a block — treat the percentages as "
                "indicative and fly a full pass before spraying on them."
            )

        full_summary = {
            "run_id": run.id,
            "camera_mode": run.camera_mode,
            "detection_target": run.detection_target,
            "crop": run.crop,
            "crop_name": (get_crop(run.crop) or {}).get("name"),
            "field_name": run.field_name,
            "health": health,
            "scan": summary,
            "treatments": treatments,
            "tank_plan": tank_plan,
            "action_plan": SurveyService._action_plan(
                summary, treatments, tank_plan,
                has_map=bool(prescription and prescription.get("patch_count")),
            ),
            "prescription": prescription,
            "advisor": advisor_capabilities(),
            "notes": notes,
            "disclaimer": (
                "Automated screening from drone imagery. It narrows the "
                "possibilities; it does not confirm a pathogen. Walk the worst "
                "spots and confirm before any chemical goes in the tank."
            ),
        }

        run.status = "analysed"
        run.finished_at = datetime.now()
        run.frames_scanned = summary.get("frames", 0)
        run.diseased_frames = summary.get("diseased_frames", 0)
        run.weed_percent = int(
            round(float((summary.get("weed") or {}).get("mean_coverage") or 0.0) * 100)
        )
        run.health_score = health["score"]
        run.dominant_condition = (summary.get("dominant_problem") or {}).get("name")
        if prescription and prescription.get("prescription_id"):
            run.prescription_id = prescription["prescription_id"]
        run.summary = SurveyService._dump(full_summary)
        SurveyRepository.save()

        return {
            "status": "ok",
            "message": f"Survey #{run.id} complete — {health['headline']}",
            "run": run.to_dict(),
            "summary": full_summary,
        }, 200

    # -- the map -----------------------------------------------------------

    @staticmethod
    def _build_map(
        run: SurveyRun,
        scans: List[Dict[str, Any]],
        payload: Dict[str, Any],
        capture_base: str,
        output_base: str,
        url_prefix: str,
        user_id: Optional[int],
    ) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
        """K-means over whatever this run's cameras produced.

        Multispectral wins where both are present: clustering a calibrated
        index is a measurement of the crop, while clustering detections is a
        measurement of where the aircraft happened to be when it saw one.
        """
        if run.uses_multispectral:
            result, note = SurveyService._multispectral_map(
                run, payload, capture_base, output_base, url_prefix, user_id
            )
            if result is not None:
                return result, note
            # Fall through to the detections when the bands could not answer,
            # rather than leaving a 'both' run with no map at all.
            if run.uses_rgb and scans:
                fallback, hotspot_note = SurveyService._hotspot_map(
                    run, scans, output_base, url_prefix, user_id
                )
                joined = " ".join(filter(None, [note, hotspot_note]))
                return fallback, joined or None
            return None, note

        if not scans:
            return None, None
        return SurveyService._hotspot_map(
            run, scans, output_base, url_prefix, user_id
        )

    @staticmethod
    def _multispectral_map(
        run: SurveyRun,
        payload: Dict[str, Any],
        capture_base: str,
        output_base: str,
        url_prefix: str,
        user_id: Optional[int],
    ) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
        frames = CaptureFrameRepository.list_frames(
            user_id=user_id, session_id=run.session_id, limit=200
        )
        shots = [f.shot_id for f in frames if f.role == "multispectral" and f.shot_id]
        if not shots:
            return None, (
                "No multispectral shot was captured during this survey, so no "
                "index-based zone map could be built."
            )

        # Newest shot by default: it is the one the operator most recently
        # judged worth taking, and they can prescribe from an older one by hand.
        shot_id = str(payload.get("shot_id") or shots[0])

        result, status = SprayService.prescribe(
            {
                "shot_id": shot_id,
                "k": payload.get("k") or 3,
                "index": payload.get("index"),
                "field_area_ha": payload.get("field_area_ha"),
            },
            capture_base=capture_base,
            output_base=output_base,
            url_prefix=url_prefix,
            user_id=user_id,
        )
        if status != 200:
            return None, result.get("message")

        result["source"] = "multispectral"
        return result, None

    @staticmethod
    def _hotspot_map(
        run: SurveyRun,
        scans: List[Dict[str, Any]],
        output_base: str,
        url_prefix: str,
        user_id: Optional[int],
    ) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
        job_dir = os.path.join(output_base, run.session_id)
        config = spray_config()

        try:
            result = cluster_detections(
                samples=scans,
                output_dir=job_dir,
                k=3,
                swath_m=config.get("swath_m", 3.0),
                crop=run.crop,
            )
        except HotspotError as exc:
            return None, str(exc)
        except Exception as exc:  # pragma: no cover - defensive
            logger.exception("Hotspot clustering failed for run %s", run.id)
            return None, f"The treatment map could not be built: {exc}"

        result["session_id"] = run.session_id
        result["shot_id"] = run.session_id  # no shutter on this path; the pass is the unit
        result["field_name"] = run.field_name
        result["spray_hardware"] = config
        result["geojson"] = hotspot_geojson(result)
        SprayService._urlify(result, output_base, url_prefix)

        record = SprayService._record(result, user_id=user_id)
        if record is not None:
            result["prescription_id"] = record.id

        return result, None

    # -- summary -----------------------------------------------------------

    @staticmethod
    def _health(summary: Dict[str, Any], run: SurveyRun) -> Dict[str, Any]:
        """One number and one sentence for the top of the summary screen.

        The score is deliberately blunt: it starts at 100 and is docked for
        disease incidence, worst severity and weed cover. Its value is not
        precision, it is that two flights over the same block a week apart are
        comparable — which is the question a farmer actually asks.
        """
        frames = summary.get("frames", 0)
        if not frames:
            return {
                "score": None,
                "band": "unknown",
                "headline": "nothing was scanned on this pass",
                "detail": "No frame from this survey could be scanned, so there "
                          "is no health reading. Check the camera and fly again.",
            }

        incidence = float(summary.get("disease_incidence") or 0.0)
        weed_coverage = float((summary.get("weed") or {}).get("mean_coverage") or 0.0)
        dominant = summary.get("dominant_problem") or {}
        worst = str(dominant.get("worst_severity") or "none").lower()

        score = 100.0
        score -= incidence * 45.0                      # how much of the pass is affected
        score -= min(weed_coverage / 0.25, 1.0) * 30.0  # weeds, capped at 25% cover
        score -= {"high": 20.0, "moderate": 10.0, "low": 4.0}.get(worst, 0.0)
        score = int(max(0, min(100, round(score))))

        if score >= 85:
            band, headline = "good", "the crop is in good shape"
        elif score >= 65:
            band, headline = "fair", "the crop is mostly healthy with problems starting"
        elif score >= 40:
            band, headline = "poor", "a real problem is spreading in this block"
        else:
            band, headline = "critical", "this block needs attention now"

        parts = [f"{frames} frame(s) scanned across the pass."]
        if run.detects_disease:
            parts.append(
                f"{summary.get('diseased_frames', 0)} of them show a disease "
                f"pattern ({int(round(incidence * 100))}%)."
                if incidence else "No disease pattern stood out."
            )
        if run.detects_weeds:
            parts.append(
                f"Weed cover averages {int(round(weed_coverage * 100))}% of the "
                f"ground ({(summary.get('weed') or {}).get('level', 'unknown')} "
                "pressure)."
            )
        if dominant.get("name"):
            parts.append(
                f"{dominant['name']} is the dominant problem, in "
                f"{int(round(float(dominant.get('frame_share') or 0) * 100))}% "
                "of frames."
            )

        return {
            "score": score,
            "band": band,
            "headline": headline,
            "detail": " ".join(parts),
            "confident": frames >= MIN_FRAMES_FOR_CONFIDENCE,
        }

    @staticmethod
    def _action_plan(
        summary: Dict[str, Any],
        treatments: List[Dict[str, Any]],
        tank_plan: Dict[str, Any],
        has_map: bool = False,
    ) -> List[Dict[str, Any]]:
        """What to do, worst first, with the chemical decision attached.

        The scan's own actions ("confirm X on the ground") are agronomy advice.
        This adds the step that was missing between advice and a flight: which
        product, in which tank, and whether the drone can deliver it at all.
        """
        # How soon each condition needs treating, so a tank for something
        # "urgent" sorts above one for something "routine" rather than every
        # spray row landing at the same priority.
        urgency_by_condition = {
            found.get("condition"): found.get("urgency", "routine")
            for found in treatments or []
        }

        actions: List[Dict[str, Any]] = []
        for action in summary.get("actions") or []:
            # The field-scan aggregate tells an operator to go and build a
            # prescription. Inside a survey that has already happened three
            # lines further down the same screen, and repeating it reads as a
            # step they still have to take.
            if has_map and action.get("category") == "spray":
                action = {
                    **action,
                    "detail": "The treatment map below is aimed at exactly "
                              "these spots.",
                }
            actions.append(action)

        for entry in tank_plan.get("passes", []):
            load = entry.get("load")
            if not load:
                continue
            urgencies = {
                urgency_by_condition.get(target, "routine")
                for target in entry.get("targets", [])
            }
            actions.append({
                "priority": 1 if "urgent" in urgencies else 2,
                "category": "spray",
                "title": f"Load {load['name']} — {load['dose_per_acre']} per acre "
                         f"in {load['water_per_acre']} of water",
                "detail": (
                    f"Covers: {', '.join(entry.get('targets', []))}. "
                    f"{load.get('timing', '')}"
                    + (f" {load['note']}" if load.get("note") else "")
                ).strip(),
                "product": load,
                "pass": entry.get("pass"),
            })

        for blocked in tank_plan.get("not_sprayable", []):
            # Two different situations wearing the same shape: a condition no
            # spray can treat, and one that is simply not bad enough to be
            # worth a tank. Telling a farmer their light weed pressure "cannot
            # be sprayed" is wrong, and it is the kind of wrong that makes
            # them distrust the rest of the report.
            not_worth_it = "below the level" in (blocked.get("why") or "")
            actions.append({
                "priority": 3 if not_worth_it else 2,
                "category": "no_spray",
                "title": (
                    f"{blocked['condition']} — not worth a spray yet"
                    if not_worth_it
                    else f"{blocked['condition']} cannot be sprayed"
                ),
                "detail": blocked.get("why", ""),
                "instead": blocked.get("instead", []),
            })

        if tank_plan.get("needs_separate_passes"):
            actions.append({
                "priority": 2,
                "category": "spray",
                "title": f"{tank_plan['pass_count']} separate tanks are needed",
                "detail": "These products should not share a load. Fly them as "
                          "separate passes, refilling in between.",
            })

        actions.sort(key=lambda action: action.get("priority", 3))
        for order, action in enumerate(actions, 1):
            action["order"] = order
        return actions

    @staticmethod
    def summary(
        run_id: int, user_id: Optional[int] = None
    ) -> Tuple[Dict[str, Any], int]:
        """Re-open a finished run without re-scanning anything."""
        run, error = SurveyService._owned(run_id, user_id)
        if error:
            return error
        if not run.summary:
            return _fail(
                f"Survey #{run.id} has not been finished yet, so there is no "
                "summary. End the pass first.",
                409,
            )
        return {
            "status": "ok",
            "run": run.to_dict(),
            "summary": run.summary_dict(),
        }, 200

    @staticmethod
    def list_runs(
        user_id: Optional[int] = None, limit: int = 50
    ) -> Tuple[Dict[str, Any], int]:
        runs = SurveyRepository.list_runs(user_id=user_id, limit=limit)
        return {
            "status": "ok",
            "runs": [run.to_dict() for run in runs],
            "active": next(
                (r.to_dict() for r in runs if r.status in ("planned", "flying")), None
            ),
        }, 200

    @staticmethod
    def cancel(
        run_id: int, user_id: Optional[int] = None
    ) -> Tuple[Dict[str, Any], int]:
        run, error = SurveyService._owned(run_id, user_id)
        if error:
            return error
        if run.rgb_camera_id is not None:
            LiveAnalysisService.stop(str(run.rgb_camera_id))
        run.status = "cancelled"
        run.finished_at = datetime.now()
        SurveyRepository.save()
        return {
            "status": "ok",
            "message": f"Survey #{run.id} cancelled.",
            "run": run.to_dict(),
        }, 200

    # -- authorise the spray -----------------------------------------------

    @staticmethod
    def authorise(
        run_id: int,
        payload: Optional[Dict],
        user_id: Optional[int] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Record the tank and the permission, then fly the map.

        Payload::

            {"tank_filled": true, "tank_litres": 10, "tank_product": "...",
             "authorised_by": "Ramesh", "option": "severe_only",
             "start": true}

        The two confirmations are checked separately and both are required.
        ``start`` is what actually opens a valve over a field, so it stays a
        third, explicit flag — an operator can load the plan onto the aircraft
        on the ground and launch it when the field is clear.
        """
        run, error = SurveyService._owned(run_id, user_id)
        if error:
            return error

        payload = payload if isinstance(payload, dict) else {}

        if run.status == "cancelled":
            return _fail(f"Survey #{run.id} was cancelled.", 409)
        if not run.summary:
            return _fail(
                "This survey has not been summarised yet, so there is nothing "
                "to spray. Finish the pass first.",
                409,
            )
        if run.prescription_id is None:
            return _fail(
                "This survey produced no treatment map, so there is nowhere to "
                "send the aircraft. Re-fly the block with a camera that can "
                "produce one.",
                409,
            )

        if not bool(payload.get("tank_filled")):
            return _fail(
                "Confirm the tank is filled before authorising a spray. The "
                "aircraft will fly the whole prescription whether or not there "
                "is anything in it.",
                409,
            )
        if not bool(payload.get("spray_authorised", payload.get("authorised", True))):
            return _fail("Spraying was not authorised.", 409)

        summary = run.summary_dict()
        tank_plan = summary.get("tank_plan") or {}
        if not tank_plan.get("passes"):
            return _fail(
                "The survey found nothing that a spray would help. "
                + (tank_plan.get("note") or ""),
                409,
            )

        try:
            litres = payload.get("tank_litres")
            litres = float(litres) if litres not in (None, "") else None
        except (TypeError, ValueError):
            return _fail("tank_litres must be a number.")

        run.tank_filled = True
        run.tank_litres = litres
        run.tank_product = (
            str(payload.get("tank_product") or "").strip()
            or ((tank_plan.get("passes") or [{}])[0].get("load") or {}).get("name")
        )
        run.spray_authorised = True
        run.authorised_by = str(payload.get("authorised_by") or "").strip() or None
        run.authorised_at = datetime.now()
        run.chosen_option = str(payload.get("option") or "severe_only").strip().lower()
        run.status = "authorised"
        SurveyRepository.save()

        # Everything above is a record of a decision, and it stands whether or
        # not the aircraft accepts the mission. Only now does anything reach it.
        result, status = SprayService.execute(
            run.prescription_id,
            {
                "option": run.chosen_option,
                "start": bool(payload.get("start")),
                "altitude_m": payload.get("altitude_m"),
                "speed_ms": payload.get("speed_ms"),
            },
            user_id=user_id,
        )

        if status != 200:
            # Keep the authorisation recorded: the farmer did fill the tank and
            # did give permission, and losing that on an upload failure would
            # make them do it again for no reason.
            result.setdefault("run", run.to_dict())
            result["authorisation_recorded"] = True
            return result, status

        run.status = "spraying" if payload.get("start") else "authorised"
        SprayRepository.save()
        SurveyRepository.save()

        return {
            **result,
            "run": run.to_dict(),
            "tank": {
                "filled": True,
                "litres": litres,
                "product": run.tank_product,
            },
        }, 200

    # -- shared ------------------------------------------------------------

    @staticmethod
    def _owned(run_id: int, user_id: Optional[int]):
        run = SurveyRepository.get_by_id(run_id)
        if run is None:
            return None, _fail("No such survey.", 404)
        if run.user_id is not None and user_id is not None and run.user_id != user_id:
            return None, _fail("Not your survey.", 403)
        return run, None

    @staticmethod
    def _dump(payload: Dict[str, Any]) -> Optional[str]:
        import json

        try:
            return json.dumps(payload)
        except (TypeError, ValueError) as exc:  # pragma: no cover - defensive
            logger.warning("Could not store survey summary: %s", exc)
            return None
