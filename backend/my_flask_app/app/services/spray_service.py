"""Service layer for targeted (variable-rate) spraying.

The chain this owns, end to end:

    a multispectral shot  ->  K-means prescription  ->  costed options
                          ->  the operator picks one
                          ->  a spray mission on the vehicle

Two rules shape the whole module:

1. **The operator commands the spray, never the backend.** ``prescribe`` only
   ever produces a proposal. Nothing reaches the aircraft until a later call
   names the option that was chosen, and ``execute`` will not launch unless it
   is explicitly told to.
2. **The saving quoted must be the saving the hardware can deliver.** The
   reduced rate over moderate zones is only real on a proportional valve, so
   the options are re-costed against the rig's actual mechanism before they
   are shown as a flight plan (see :func:`app.spray.mission.spray_config`).
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict, List, Optional, Tuple

from app.api.models.capture import CaptureFrame
from app.api.models.spray import SprayPrescription
from app.capture import absolute as capture_absolute
from app.mavlink import MavlinkError, link
from app.repositories.capture_repository import CameraRepository, CaptureFrameRepository
from app.repositories.spray_repository import SprayRepository
from app.spray import (
    DEFAULT_DOSE_L_PER_HA,
    DEFAULT_MODERATE_RATE,
    PrescriptionError,
    build_spray_mission,
    patches_for_levels,
    prescribe,
    spray_config,
)
from app.spray.mission import (
    CMD_DO_SET_RELAY,
    CMD_DO_SET_SERVO,
    CMD_DO_SPRAYER,
    pump_commands,
)

logger = logging.getLogger(__name__)

# Which severity classes each option treats. 'blanket' is deliberately absent:
# a whole-block pass is not a targeted prescription, and flying it as a set of
# patch passes would be a worse blanket spray than simply flying the survey
# grid with the pump open.
_OPTION_LEVELS = {
    "severe_only": ["severe"],
    "severe_moderate": ["severe", "moderate"],
}


def _fail(message: str, status: int = 400) -> Tuple[Dict[str, Any], int]:
    return {"status": "error", "message": message}, status


class SprayService:

    # ── capabilities ──────────────────────────────────────────────────────

    @staticmethod
    def capabilities() -> Tuple[Dict[str, Any], int]:
        config = spray_config()
        return {
            "status": "ok",
            "feature": "targeted-spray-prescription",
            "clustering": "k-means over a vegetation index (default k=3)",
            "options": list(_OPTION_LEVELS.keys()) + ["blanket"],
            "spray_hardware": config,
            "default_dose_l_per_ha": DEFAULT_DOSE_L_PER_HA,
            "default_moderate_rate": DEFAULT_MODERATE_RATE,
            "note": (
                "Variable rate needs a proportional valve (SPRAY_MECHANISM="
                "servo). On an on/off rig the moderate zones are sprayed at "
                "full rate and the saving comes from skipped ground only."
            ),
        }, 200

    # ── prescribe ─────────────────────────────────────────────────────────

    @staticmethod
    def prescribe(
        payload: Dict,
        capture_base: str,
        output_base: str,
        url_prefix: str,
        user_id: Optional[int] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Cluster a captured shot into spray zones and cost the options.

        Payload: ``{"shot_id": "...", "k": 3, "index": "ndvi",
        "dose_l_per_ha": 20, "fov_deg": 62, "field_area_ha": 1.2}``
        """
        payload = payload if isinstance(payload, dict) else {}

        shot_id = str(payload.get("shot_id") or "").strip()
        if not shot_id:
            return _fail("Which capture? Send the 'shot_id' of a multispectral shot.")

        frames = CaptureFrameRepository.list_frames(
            user_id=user_id, shot_id=shot_id, limit=32
        )
        if not frames:
            return _fail("No frames found for that shot.", 404)

        band_frames = [f for f in frames if f.band]
        band_paths = {
            f.band: capture_absolute(f.path, capture_base) for f in band_frames
        }
        missing = [b for b, p in band_paths.items() if not os.path.isfile(p)]
        for band in missing:
            band_paths.pop(band, None)

        if not {"red", "nir"}.issubset(band_paths):
            return _fail(
                "This shot has no red + NIR pair, so no vegetation index can be "
                f"computed from it (bands present: {', '.join(sorted(band_paths)) or 'none'}).",
                409,
            )

        reference = band_frames[0]
        fov_deg = payload.get("fov_deg")
        if fov_deg in (None, ""):
            fov_deg = SprayService._camera_fov(band_frames)

        try:
            k = int(payload.get("k") or 3)
            dose = float(payload.get("dose_l_per_ha") or DEFAULT_DOSE_L_PER_HA)
            moderate_rate = float(payload.get("moderate_rate") or DEFAULT_MODERATE_RATE)
            field_area_ha = payload.get("field_area_ha")
            field_area_ha = float(field_area_ha) if field_area_ha not in (None, "") else None
            fov_deg = float(fov_deg) if fov_deg not in (None, "") else None
        except (TypeError, ValueError):
            return _fail("k, dose_l_per_ha, moderate_rate, field_area_ha and fov_deg must be numbers.")

        job_dir = os.path.join(output_base, shot_id)
        try:
            result = prescribe(
                band_paths=band_paths,
                output_dir=job_dir,
                k=k,
                index=payload.get("index"),
                lat=reference.lat,
                lon=reference.lon,
                alt_m=reference.alt_m,
                heading_deg=reference.heading_deg,
                fov_deg=fov_deg,
                field_area_ha=field_area_ha,
                dose_l_per_ha=dose,
                moderate_rate=moderate_rate,
            )
        except PrescriptionError as exc:
            return _fail(str(exc))
        except (FileNotFoundError, ValueError, KeyError) as exc:
            return _fail(f"Could not read this capture: {exc}")
        except Exception as exc:  # unexpected
            logger.exception("Spray prescription failed")
            return _fail(f"Prescription failed: {exc}", 500)

        result["session_id"] = reference.session_id
        result["shot_id"] = shot_id
        result["field_name"] = reference.field_name
        result["spray_hardware"] = spray_config()
        SprayService._urlify(result, output_base, url_prefix)

        record = SprayService._record(result, user_id=user_id)
        if record is not None:
            result["prescription_id"] = record.id

        return result, 200

    @staticmethod
    def _camera_fov(frames: List[CaptureFrame]) -> Optional[float]:
        """Field of view from whichever camera took these frames."""
        for frame in frames:
            if frame.camera_id is None:
                continue
            camera = CameraRepository.get_by_id(frame.camera_id)
            if camera is not None and camera.fov_deg:
                return camera.fov_deg
        return None

    @staticmethod
    def _urlify(result: Dict, base_dir: str, url_prefix: str) -> None:
        """Rewrite generated file paths as URLs the app can fetch."""
        outputs = result.get("outputs") or {}
        for key, path in list(outputs.items()):
            if not isinstance(path, str) or not path:
                continue
            try:
                relative = os.path.relpath(path, base_dir).replace(os.sep, "/")
            except ValueError:
                continue
            if relative.startswith(".."):
                continue
            outputs[key] = f"{url_prefix.rstrip('/')}/{relative}"
            outputs.setdefault("_paths", {})[key] = relative

    @staticmethod
    def _record(result: Dict, user_id: Optional[int]) -> Optional[SprayPrescription]:
        """Persist the proposal. A storage failure must not lose the plan the
        operator is looking at — they can still act on the response."""
        try:
            fractions = result.get("targeted_fractions") or {}
            paths = (result.get("outputs") or {}).get("_paths") or {}
            prescription = SprayPrescription(
                user_id=user_id,
                session_id=result.get("session_id"),
                shot_id=result.get("shot_id"),
                field_name=result.get("field_name"),
                index_key=result.get("index"),
                k=result.get("k"),
                severe_fraction=fractions.get("severe", 0.0),
                moderate_fraction=fractions.get("moderate", 0.0),
                healthy_fraction=fractions.get("healthy", 0.0),
                patch_count=result.get("patch_count", 0),
                field_ha=result.get("field_ha"),
                status="proposed",
                map_path=paths.get("prescription_map"),
                detail=json.dumps(result),
            )
            return SprayRepository.create(prescription)
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Could not record spray prescription: %s", exc)
            return None

    # ── history ───────────────────────────────────────────────────────────

    @staticmethod
    def list_prescriptions(
        user_id: Optional[int] = None, session_id: Optional[str] = None
    ) -> Tuple[Dict, int]:
        rows = SprayRepository.list_prescriptions(user_id=user_id, session_id=session_id)
        return {
            "status": "ok",
            "prescriptions": [r.to_dict() for r in rows],
        }, 200

    @staticmethod
    def get(prescription_id: int, user_id: Optional[int] = None) -> Tuple[Dict, int]:
        prescription, error = SprayService._owned(prescription_id, user_id)
        if error:
            return error
        return {"status": "ok", "prescription": prescription.to_dict(include_detail=True)}, 200

    @staticmethod
    def _owned(prescription_id: int, user_id: Optional[int]):
        prescription = SprayRepository.get_by_id(prescription_id)
        if prescription is None:
            return None, _fail("Prescription not found.", 404)
        if (
            prescription.user_id is not None
            and user_id is not None
            and prescription.user_id != user_id
        ):
            return None, _fail("Not your prescription.", 403)
        return prescription, None

    # ── plan ──────────────────────────────────────────────────────────────

    @staticmethod
    def plan(
        prescription_id: int,
        payload: Dict,
        user_id: Optional[int] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Build (but do not upload) the spray mission for a chosen option.

        This is the confirmation screen's data: exactly what the aircraft would
        fly, how long it would take, and how much chemical it would use.
        """
        prescription, error = SprayService._owned(prescription_id, user_id)
        if error:
            return error

        payload = payload if isinstance(payload, dict) else {}
        detail = prescription.detail_dict()

        levels, level_error = SprayService._levels_for(payload, detail)
        if level_error:
            return level_error

        targets = patches_for_levels(detail, levels)
        if not targets:
            return _fail(
                "That option has no patches to spray — nothing in the capture "
                "was classed that way, or the affected areas were too small to "
                "target.",
                409,
            )

        config = spray_config()
        try:
            altitude_m = payload.get("altitude_m")
            speed_ms = payload.get("speed_ms")
            altitude_m = float(altitude_m) if altitude_m not in (None, "") else None
            speed_ms = float(speed_ms) if speed_ms not in (None, "") else None
        except (TypeError, ValueError):
            return _fail("altitude_m and speed_ms must be numbers.")

        heading = (detail.get("coverage") or {}).get("heading_deg") or 0.0

        try:
            built = build_spray_mission(
                targets=targets,
                altitude_m=altitude_m,
                speed_ms=speed_ms,
                heading_deg=heading,
                config=config,
                moderate_rate=detail.get("moderate_rate", DEFAULT_MODERATE_RATE),
            )
        except ValueError as exc:
            return _fail(str(exc), 409)

        economics = SprayService._economics(detail, levels, config)

        return {
            "status": "ok",
            "message": f"Spray plan ready for {len(targets)} patch(es).",
            "prescription_id": prescription.id,
            "option": payload.get("option") or SprayService._option_for(levels),
            "levels": levels,
            "targets": targets,
            "summary": built["summary"],
            "items": built["items"],
            "economics": economics,
            "spray_hardware": config,
        }, 200

    @staticmethod
    def _levels_for(payload: Dict, detail: Dict):
        """Resolve the operator's choice into severity levels."""
        option = str(payload.get("option") or "").strip().lower()
        levels = payload.get("levels")

        if option == "blanket":
            return None, _fail(
                "A blanket spray is not a targeted prescription — fly the "
                "survey grid with the pump open for that. Choose "
                "'severe_only' or 'severe_moderate' to spray the prescription.",
            )
        if option:
            if option not in _OPTION_LEVELS:
                return None, _fail(
                    f"Unknown option '{option}'. Expected one of: "
                    f"{', '.join(_OPTION_LEVELS)}."
                )
            return list(_OPTION_LEVELS[option]), None

        if isinstance(levels, list) and levels:
            cleaned = [str(v).lower() for v in levels if str(v).lower() in ("severe", "moderate")]
            if cleaned:
                return cleaned, None

        return None, _fail(
            "Say what to spray: 'option': 'severe_only' or 'severe_moderate'."
        )

    @staticmethod
    def _option_for(levels: List[str]) -> str:
        return "severe_moderate" if "moderate" in levels else "severe_only"

    @staticmethod
    def _economics(detail: Dict, levels: List[str], config: Dict) -> Dict:
        """Re-cost the chosen option against what this rig can actually do.

        The prescription assumed a reduced rate over the moderate zones. On an
        on/off pump that reduction does not exist, so the honest saving is
        smaller — and the operator should see the smaller number before they
        commit chemical to it.
        """
        fractions = detail.get("targeted_fractions") or {}
        areas = detail.get("areas_ha") or {}
        dose = float(detail.get("dose_l_per_ha") or DEFAULT_DOSE_L_PER_HA)
        moderate_rate = (
            float(detail.get("moderate_rate") or DEFAULT_MODERATE_RATE)
            if config.get("variable_rate") else 1.0
        )
        field_ha = detail.get("field_ha")

        treated_fraction = sum(float(fractions.get(level) or 0.0) for level in levels)
        chemical_fraction = sum(
            float(fractions.get(level) or 0.0) * (1.0 if level == "severe" else moderate_rate)
            for level in levels
        )

        economics = {
            "levels": levels,
            "treated_fraction": round(treated_fraction, 4),
            "treated_percent": int(round(treated_fraction * 100)),
            "chemical_fraction": round(chemical_fraction, 4),
            "saving_percent": int(round((1.0 - chemical_fraction) * 100)),
            "moderate_rate_applied": moderate_rate,
            "variable_rate": bool(config.get("variable_rate")),
            "dose_l_per_ha": dose,
        }
        if field_ha:
            chemical_l = sum(
                float(areas.get(level) or 0.0)
                * dose
                * (1.0 if level == "severe" else moderate_rate)
                for level in levels
            )
            blanket_l = float(field_ha) * dose
            economics.update({
                "treated_ha": round(
                    sum(float(areas.get(level) or 0.0) for level in levels), 4
                ),
                "field_ha": round(float(field_ha), 4),
                "chemical_l": round(chemical_l, 2),
                "blanket_l": round(blanket_l, 2),
                "saved_l": round(max(0.0, blanket_l - chemical_l), 2),
            })
        return economics

    # ── execute ───────────────────────────────────────────────────────────

    @staticmethod
    def execute(
        prescription_id: int,
        payload: Dict,
        user_id: Optional[int] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Upload the spray mission to the vehicle, and launch when asked.

        ``start: true`` is what actually opens a valve over a field, so it is
        opt-in and separate from the upload — an operator can load the plan on
        the bench and fly it later.
        """
        payload = payload if isinstance(payload, dict) else {}

        plan, status = SprayService.plan(prescription_id, payload, user_id=user_id)
        if status != 200:
            return plan, status

        if not link.is_available():
            return _fail(
                "pymavlink is not installed on the server, so no mission can be "
                "sent to the aircraft. Run: pip install pymavlink",
                503,
            )
        if not link.is_connected:
            return _fail(
                "No vehicle connected. Open the MAVLink link before sending a "
                "spray mission.",
                409,
            )

        try:
            result = link.upload_items(plan["items"])
        except MavlinkError as exc:
            return _fail(str(exc), 502)
        except ValueError as exc:
            return _fail(str(exc))
        except Exception as exc:  # unexpected
            logger.exception("Spray mission upload failed")
            return _fail(f"Spray mission upload failed: {exc}", 500)

        prescription, error = SprayService._owned(prescription_id, user_id)
        if error:  # pragma: no cover - it existed a moment ago
            return error

        economics = plan["economics"]
        prescription.chosen_option = plan["option"]
        prescription.treated_fraction = economics.get("treated_fraction")
        prescription.saving_percent = economics.get("saving_percent")
        prescription.chemical_l = economics.get("chemical_l")
        prescription.saved_l = economics.get("saved_l")
        prescription.status = "uploaded"
        SprayRepository.save()

        response = {
            "status": "ok",
            "message": f"Uploaded {result['uploaded']} spray mission items.",
            "prescription_id": prescription.id,
            "option": plan["option"],
            "uploaded": result["uploaded"],
            "summary": plan["summary"],
            "economics": economics,
            **link.snapshot(),
        }

        if not bool(payload.get("start")):
            response["message"] += " Send start=true (or launch from the live "
            response["message"] += "screen) when the field is clear."
            return response, 200

        try:
            launch = link.start_mission()
        except MavlinkError as exc:
            # The plan is on the vehicle; only the launch failed. Say exactly
            # that, so the operator doesn't re-upload a mission that is already
            # loaded.
            return {
                "status": "error",
                "message": f"Spray mission uploaded, but it did not start: {exc}",
                "prescription_id": prescription.id,
                "uploaded": result["uploaded"],
                **link.snapshot(),
            }, 502
        except Exception as exc:
            logger.exception("Spray mission start failed")
            return _fail(f"Spray mission uploaded but could not start: {exc}", 500)

        prescription.status = "sprayed"
        SprayRepository.save()

        response["message"] = "Spraying — the aircraft is flying the prescription."
        response["detail"] = launch
        response.update(link.snapshot())
        return response, 200

    @staticmethod
    def stop(payload: Optional[Dict] = None) -> Tuple[Dict[str, Any], int]:
        """Shut the valve now, and hold position.

        The order matters: close the pump *first*, then stop the aircraft. Ask
        for the loiter first and a slow mode change keeps the boom open over
        whatever the drone drifts across meanwhile.
        """
        if not link.is_available():
            return _fail("pymavlink is not installed on the server.", 503)
        if not link.is_connected:
            return _fail("No vehicle connected.", 409)

        config = spray_config()
        steps = []
        errors = []

        for item in pump_commands(False, 0.0, config):
            command = item["command"]
            label = {
                CMD_DO_SPRAYER: "sprayer off",
                CMD_DO_SET_SERVO: "spray valve closed",
                CMD_DO_SET_RELAY: "spray relay off",
            }.get(command, "spray off")
            try:
                steps.append(
                    link.send_command_long(
                        command,
                        params=(item.get("param1", 0.0), item.get("param2", 0.0)),
                        label=label,
                    )
                )
            except MavlinkError as exc:
                errors.append(str(exc))
            except Exception as exc:
                errors.append(f"{label}: {exc}")

        hold_requested = bool((payload or {}).get("hold", True))
        if hold_requested:
            try:
                steps.append(link.hold())
            except MavlinkError as exc:
                errors.append(str(exc))
            except Exception as exc:
                errors.append(f"hold: {exc}")

        if errors and not steps:
            return {
                "status": "error",
                "message": "Could not stop the spray: " + "; ".join(errors),
                **link.snapshot(),
            }, 502

        return {
            "status": "ok",
            "message": "Spray stopped." + (" Aircraft holding." if hold_requested else ""),
            "steps": steps,
            "warnings": errors,
            **link.snapshot(),
        }, 200
