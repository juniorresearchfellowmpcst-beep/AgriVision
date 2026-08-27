"""The crop catalogue, and scanning a crop with the phone.

Two things live here, and they are the same feature seen from two ends.

**The catalogue** is what the app's crop picker is built from: every crop the
detectors know, every disease within it, the weeds that go with it, and -- new
here -- the treatment behind each one. Previously the app could show a farmer
"Yellow Mosaic Virus" and its symptoms and then stop, one question short of
the only one that matters.

**The phone scan** is the drone-free path. A farmer standing in the field with
a suspicious leaf does not want to charge a battery, fit a camera and fly a
survey; they want to point their phone at it. So the same detectors that run on
the aircraft's video feed also run on a single phone photo, with the crop chosen
first -- the crop is part of the diagnosis, because the same yellowing is yellow
rust in wheat and yellow mosaic in soybean.

The one deliberate asymmetry between the two paths: a phone scan is never
turned into a spray prescription. A photo of one leaf cannot say where in the
block the problem is, and a treatment map built from a single point would be a
map of where the farmer happened to be standing.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

from app.ai import treatment_kb
from app.ai.crop_kb import CROPS, get_crop, list_crops
from app.ai.gemini_advisor import capabilities as advisor_capabilities
from app.ai.weed_kb import WEED_TYPES, list_weeds
from app.services.field_scan_service import FieldScanService

logger = logging.getLogger(__name__)

# The weed picker sits in the crop grid alongside the crops, because that is
# where a farmer looks for it -- it is not a crop, but "what is growing in my
# field that should not be" is the same question asked from the other side.
WEED_ENTRY = {
    "id": "weeds",
    "name": "Weeds",
    "local_name": "Kharpatwar / खरपतवार",
    "season": "all",
    "kind": "weeds",
    "note": "Identify what is competing with the crop, and how heavy the "
            "pressure is. Pick the crop as well for a herbicide that will not "
            "damage it.",
}

# Rough sowing-to-harvest windows, so the picker can show a farmer whether the
# crop they picked is even in the ground right now. Months are 1-12 and wrap.
_SEASON_MONTHS = {
    "kharif": (6, 11),   # sown with the monsoon, harvested after it
    "rabi": (10, 4),     # sown into the cool season, harvested in spring
    "all": (1, 12),
}


def _fail(message: str, status: int = 400) -> Tuple[Dict[str, Any], int]:
    return {"status": "error", "message": message}, status


def _in_season(season: str, month: int) -> bool:
    start, end = _SEASON_MONTHS.get(str(season or "").lower(), (1, 12))
    if start <= end:
        return start <= month <= end
    return month >= start or month <= end  # a window that wraps the new year


class CropService:
    """Catalogue reads and phone-camera scans."""

    # -- catalogue ---------------------------------------------------------

    @staticmethod
    def catalog(month: Optional[int] = None) -> Tuple[Dict[str, Any], int]:
        """Every crop the app can scan, for the picker grid.

        ``month`` (1-12) marks which crops are in season. The picker sorts
        those first: in August a farmer in MP is looking at soybean and paddy,
        and making them scroll past wheat to reach it is a small daily tax.
        """
        crops: List[Dict[str, Any]] = []
        for crop in list_crops():
            entry = dict(crop)
            entry["kind"] = "crop"
            entry["weed_count"] = len(list_weeds(crop["id"]))
            entry["has_herbicide_guidance"] = crop["id"] in treatment_kb.HERBICIDES
            if month:
                entry["in_season"] = _in_season(crop.get("season", ""), month)
            crops.append(entry)

        if month:
            crops.sort(key=lambda c: (not c.get("in_season"), c["name"]))

        weeds_entry = dict(WEED_ENTRY)
        weeds_entry["disease_count"] = 0
        weeds_entry["weed_count"] = len(list_weeds())
        if month:
            weeds_entry["in_season"] = True

        return {
            "status": "ok",
            "crops": crops,
            # Kept as a separate key rather than mixed into `crops`: an app
            # rendering a grid wants them together, and anything iterating
            # crops to run a disease model must not be handed a non-crop.
            "weeds_option": weeds_entry,
            "weed_types": list(WEED_TYPES),
            "scan_modes": [
                {"id": "disease", "name": "Disease", "detail": "Diagnose a sick plant."},
                {"id": "weed", "name": "Weeds",
                 "detail": "Measure weed pressure and name the likely species."},
                {"id": "both", "name": "Both", "detail": "Run both detectors."},
            ],
            "advisor": advisor_capabilities(),
        }, 200

    @staticmethod
    def crop_detail(crop_id: str) -> Tuple[Dict[str, Any], int]:
        """One crop: its diseases with treatments, and its usual weeds."""
        if str(crop_id).strip().lower() == "weeds":
            return CropService.weed_catalog(None)

        crop = get_crop(crop_id)
        if crop is None:
            return _fail(
                f"Unknown crop '{crop_id}'. Known crops: "
                + ", ".join(sorted(CROPS.keys())) + ".",
                404,
            )

        diseases = []
        for disease in crop["diseases"]:
            treatment = treatment_kb.treatment_for(disease["id"])
            diseases.append({
                **disease,
                "treatment": treatment,
                # Lifted out of the treatment so a list row can show it without
                # unpacking the whole entry.
                "sprayable": treatment["sprayable"],
                "urgency": treatment["urgency"],
            })

        return {
            "status": "ok",
            "crop": {
                "id": crop["id"],
                "name": crop["name"],
                "local_name": crop.get("local_name", ""),
                "season": crop.get("season", ""),
                "note": crop.get("note", ""),
                "kind": "crop",
            },
            "diseases": diseases,
            "weeds": list_weeds(crop["id"]),
            "herbicides": treatment_kb.HERBICIDES.get(crop["id"], []),
            "disclaimer": treatment_kb.DISCLAIMER,
        }, 200

    @staticmethod
    def disease_detail(
        crop_id: str, disease_id: str
    ) -> Tuple[Dict[str, Any], int]:
        """One disease in full: symptoms, what favours it, and what to spray."""
        crop = get_crop(crop_id)
        if crop is None:
            return _fail(f"Unknown crop '{crop_id}'.", 404)

        key = str(disease_id).strip().lower()
        disease = next((d for d in crop["diseases"] if d["id"] == key), None)
        if disease is None:
            return _fail(
                f"{crop['name']} has no condition '{disease_id}' in this app.", 404
            )

        return {
            "status": "ok",
            "crop": {"id": crop["id"], "name": crop["name"]},
            "disease": disease,
            "treatment": treatment_kb.treatment_for(key),
            "advisor": advisor_capabilities(),
            "disclaimer": treatment_kb.DISCLAIMER,
        }, 200

    @staticmethod
    def weed_catalog(crop_id: Optional[str] = None) -> Tuple[Dict[str, Any], int]:
        """The weeds, narrowed to one crop's usual suspects when asked."""
        if crop_id and not get_crop(crop_id):
            return _fail(f"Unknown crop '{crop_id}'.", 404)

        return {
            "status": "ok",
            "crop": (
                {"id": get_crop(crop_id)["id"], "name": get_crop(crop_id)["name"]}
                if crop_id else None
            ),
            "weeds": list_weeds(crop_id),
            "weed_types": list(WEED_TYPES),
            "herbicides": treatment_kb.HERBICIDES.get(
                str(crop_id or "").lower(), []
            ),
            "note": (
                "" if crop_id else
                "Pick a crop as well to see herbicides that will not damage it "
                "— the same product that clears wheat will kill soybean."
            ),
            "disclaimer": treatment_kb.DISCLAIMER,
        }, 200

    # -- phone scan --------------------------------------------------------

    @staticmethod
    def scan(
        image_bytes: bytes,
        crop: Optional[str],
        output_base: str,
        url_prefix: str,
        mode: str = "both",
        filename: Optional[str] = None,
        user_id: Optional[int] = None,
        field_name: Optional[str] = None,
        lat: Optional[float] = None,
        lon: Optional[float] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Scan one photo from the phone, with the crop chosen first.

        Runs the same detectors as the aircraft and then adds what the drone
        flow adds: the treatment, with an actual product. ``mode`` is
        ``disease``, ``weed`` or ``both``; ``weed`` is what the "Weeds" tile in
        the crop picker selects.
        """
        mode = str(mode or "both").strip().lower()
        if mode not in ("disease", "weed", "both"):
            return _fail("mode must be one of: disease, weed, both.")

        # "weeds" is a picker tile, not a crop. Selecting it means "look for
        # weeds", and the crop stays unknown unless the farmer also picked one.
        if str(crop or "").strip().lower() == "weeds":
            crop, mode = None, "weed"

        if crop and not get_crop(crop):
            return _fail(f"Unknown crop '{crop}'.")

        result, status = FieldScanService.analyze(
            image_bytes,
            crop=crop,
            output_base=output_base,
            url_prefix=url_prefix,
            filename=filename,
            user_id=user_id,
            field_name=field_name,
            lat=lat,
            lon=lon,
            target=mode,
        )
        if status != 200:
            return result, status

        result["source"] = "phone"
        result["mode"] = mode
        result["treatment"] = CropService._treatment_for_result(result, crop, mode)
        result["advisor"] = advisor_capabilities()
        # Said plainly, because the previous screen was a drone flow and the
        # difference is not obvious: this photo cannot become a spray run.
        result["spray_note"] = (
            "A phone photo diagnoses a plant; it cannot say where in the block "
            "the problem is. Fly a survey to build a treatment map."
        )
        return result, 200

    @staticmethod
    def _treatment_for_result(
        result: Dict[str, Any], crop: Optional[str], mode: str
    ) -> Dict[str, Any]:
        """The treatment section under a scan result.

        Both halves are answered where both ran, because a farmer looking at a
        diseased leaf in a weedy field has two problems and one flight.
        """
        payload: Dict[str, Any] = {"disclaimer": treatment_kb.DISCLAIMER}

        if mode in ("disease", "both"):
            condition_id = (result.get("disease") or {}).get("id")
            payload["disease"] = treatment_kb.treatment_for(condition_id)

        if mode in ("weed", "both"):
            pressure = ((result.get("weeds") or {}).get("pressure") or {}).get("level")
            payload["weeds"] = treatment_kb.weed_treatment_for(crop, pressure or "none")

        conditions = []
        disease = result.get("disease") or {}
        if disease.get("id") and disease["id"] != "healthy":
            conditions.append({"id": disease["id"], "name": disease.get("name")})

        payload["tank_plan"] = treatment_kb.spray_plan(
            conditions=conditions,
            crop_id=crop,
            weed_pressure=(
                ((result.get("weeds") or {}).get("pressure") or {}).get("level")
                if mode in ("weed", "both") else None
            ),
        )
        return payload
