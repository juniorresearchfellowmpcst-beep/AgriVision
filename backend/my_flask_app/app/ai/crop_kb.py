"""Crop and disease knowledge base for the Madhya Pradesh cropping system.

Scope is deliberate. MP's cultivated area is dominated by a handful of crops —
soybean and paddy in *kharif*, wheat and gram in *rabi*, with maize, mustard,
pigeonpea and cotton making up most of the rest — so those are the crops the
field-scan CNN is trained and evaluated on, and those are the diseases it can
name. Anything outside this list falls back to the generic leaf conditions in
:mod:`app.ai.knowledge_base`.

Each disease carries a **signature**: the colour and pattern its damage takes
in an aerial/canopy photo. That is what lets the heuristic path pick a
*crop-specific* answer ("wheat yellow rust") out of a generic colour/lesion
feature vector, and it is also the vocabulary a trained model's labels map
onto — see :mod:`app.ai.crop_model`.

The management advice is standard state package-of-practices guidance and is
written as decision support: every entry assumes the operator will confirm on
the ground, and doses are deliberately left to the label and the local KVK
rather than being quoted here.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

# Colour classes a canopy photo can show, matched against extracted features.
COLOURS = ("green", "yellow", "orange", "brown", "white", "grey")

# Damage patterns, in the vocabulary the feature extractor can distinguish.
PATTERNS = ("mosaic", "spots", "blotch", "coating", "streak", "chewed", "wilt")


def _disease(
    id: str,
    name: str,
    pathogen: str,
    colour: str,
    pattern: str,
    symptoms: List[str],
    conditions: str,
    management: List[str],
    severity_note: str = "",
) -> Dict[str, Any]:
    return {
        "id": id,
        "name": name,
        "pathogen": pathogen,
        "signature": {"colour": colour, "pattern": pattern},
        "symptoms": symptoms,
        "favours": conditions,
        "management": management,
        "severity_note": severity_note,
    }


# ── Crops ────────────────────────────────────────────────────────────────────

CROPS: Dict[str, Dict[str, Any]] = {
    "soybean": {
        "id": "soybean",
        "name": "Soybean",
        "local_name": "Soyabean / सोयाबीन",
        "season": "kharif",
        "note": "MP grows the largest soybean area in India; most of the crop "
                "sits in the Malwa plateau and Narmada valley.",
        "diseases": [
            _disease(
                "soybean_yellow_mosaic", "Yellow Mosaic Virus (YMV)",
                "Mungbean yellow mosaic India virus, spread by whitefly",
                "yellow", "mosaic",
                ["Bright yellow and green mosaic patches on leaves",
                 "Puckered, reduced leaflets; stunted plants",
                 "Spreads in patches that widen along the whitefly's path"],
                "Warm, dry spells that build whitefly numbers; late-sown crops.",
                ["Rogue infected plants early — the virus has no cure once in the plant",
                 "Manage the whitefly vector, not the symptom",
                 "Prefer YMV-tolerant varieties (e.g. JS 20-series) next season"],
                "Yellow area rising between two flights means the vector is active.",
            ),
            _disease(
                "soybean_charcoal_rot", "Charcoal rot",
                "Macrophomina phaseolina",
                "grey", "wilt",
                ["Patches of prematurely dying plants, often on lighter soil",
                 "Greyish-black speck-covered stem and root tissue",
                 "Leaves stay attached on dead plants"],
                "Moisture stress at pod fill with high soil temperature — the "
                "classic MP mid-season dry spell.",
                ["Irrigate if at all possible: the disease is driven by drought stress",
                 "Avoid dense stands on light soils",
                 "Rotate away from soybean where patches recur"],
                "Shows first on ridges and light-soil pockets, so the zone map "
                "often finds it before it is visible from the bund.",
            ),
            _disease(
                "soybean_anthracnose", "Anthracnose",
                "Colletotrichum truncatum",
                "brown", "blotch",
                ["Irregular dark brown blotches on stems, petioles and pods",
                 "Black speck-like fruiting bodies within the lesion",
                 "Pods fail to fill"],
                "Extended wet, humid weather during pod development.",
                ["Improve airflow — avoid over-dense sowing",
                 "Use clean, treated seed",
                 "A protective fungicide at pod initiation if wet weather persists"],
            ),
            _disease(
                "soybean_rust", "Soybean rust",
                "Phakopsora pachyrhizi",
                "orange", "spots",
                ["Small tan/reddish-brown pustules on the underside of leaves",
                 "Rapid leaf yellowing and drop from the bottom of the canopy up"],
                "Cool nights with long dew periods and a wet canopy.",
                ["Scout the lower canopy — it starts there and moves up",
                 "Fungicide decisions are stage-sensitive; consult the local KVK"],
            ),
            _disease(
                "soybean_girdle_beetle", "Girdle beetle damage",
                "Obereopsis brevis (insect pest)",
                "brown", "chewed",
                ["Two neat parallel girdles cut around the stem or petiole",
                 "The part above the girdle wilts and dries while the plant lives",
                 "Scattered dead shoots across an otherwise green canopy"],
                "Continuous soybean, especially in the Malwa belt.",
                ["Clip and destroy girdled shoots below the cut",
                 "Time any insecticide to adult emergence, not to the wilted shoots"],
                "Reads as scattered dead shoots, not as a spreading patch — a "
                "useful way to tell it from charcoal rot in an aerial frame.",
            ),
        ],
    },
    "rice": {
        "id": "rice",
        "name": "Rice (Paddy)",
        "local_name": "Dhan / धान",
        "season": "kharif",
        "note": "Grown across the eastern MP districts — Balaghat, Seoni, "
                "Mandla, Rewa — mostly transplanted and puddled.",
        "diseases": [
            _disease(
                "rice_blast", "Rice blast",
                "Magnaporthe oryzae (Pyricularia oryzae)",
                "grey", "spots",
                ["Spindle/eye-shaped lesions with grey centres and brown margins",
                 "Node and neck infection that breaks the panicle",
                 "Whitish, unfilled panicles when the neck is hit"],
                "High humidity, long dew, cloudy weather, and heavy nitrogen.",
                ["Hold back on nitrogen — excess N is the single biggest driver",
                 "Drain and dry the field where practical",
                 "Neck blast is the yield-losing stage: protect around booting"],
                "Neck blast shows up from the air as whitish panicles standing "
                "above a green canopy.",
            ),
            _disease(
                "rice_bacterial_blight", "Bacterial leaf blight",
                "Xanthomonas oryzae pv. oryzae",
                "yellow", "streak",
                ["Water-soaked streaks from the leaf tip running down the margin",
                 "Straw-yellow drying along wavy lesion edges",
                 "Whole leaves dry from the tip in severe cases"],
                "Standing water, storms and flooding that wound the leaves.",
                ["Drain the field; avoid flooding after storm damage",
                 "Stop nitrogen top-dressing while it is spreading",
                 "There is no useful fungicide — bacteria, not fungus"],
            ),
            _disease(
                "rice_brown_spot", "Brown spot",
                "Bipolaris oryzae",
                "brown", "spots",
                ["Round to oval brown spots with a grey centre, evenly scattered",
                 "Worst on nutrient-poor and unirrigated fields",
                 "Grain spotting and poor filling"],
                "Nutrient stress — especially potassium and silicon — and drought.",
                ["Treat it as a soil fertility symptom first",
                 "Correct potassium; the crop usually grows out of it",
                 "Use healthy, treated seed next season"],
            ),
            _disease(
                "rice_sheath_blight", "Sheath blight",
                "Rhizoctonia solani",
                "grey", "blotch",
                ["Oval, greenish-grey water-soaked lesions on the sheath near the waterline",
                 "Lesions with irregular purple-brown borders that climb the plant",
                 "Lodging in dense stands"],
                "Dense canopy, high nitrogen, high humidity — the tail end of kharif.",
                ["Widen spacing and avoid excess nitrogen",
                 "Drain to break canopy humidity",
                 "Scout the lower canopy — it hides under the leaves"],
            ),
        ],
    },
    "wheat": {
        "id": "wheat",
        "name": "Wheat",
        "local_name": "Gehun / गेहूँ",
        "season": "rabi",
        "note": "MP's principal rabi crop, including the durum belt around "
                "Malwa and the Sharbati wheat of Sehore/Vidisha.",
        "diseases": [
            _disease(
                "wheat_yellow_rust", "Yellow (stripe) rust",
                "Puccinia striiformis f. sp. tritici",
                "yellow", "streak",
                ["Bright yellow pustules in neat stripes between the leaf veins",
                 "Yellow powder that rubs off onto a finger or sleeve",
                 "Starts as a small circular focus and spreads outward"],
                "Cool (10–20 °C), humid weather — the January spell in north MP.",
                ["Look for the round focus patch: that is where it started",
                 "Act early — yellow rust doubles fast once a focus is established",
                 "Use recommended resistant varieties in subsequent seasons"],
                "The circular expanding focus is the giveaway from the air.",
            ),
            _disease(
                "wheat_brown_rust", "Brown (leaf) rust",
                "Puccinia triticina",
                "orange", "spots",
                ["Orange-brown round pustules scattered over the leaf blade",
                 "No striping — the pustules are random, unlike yellow rust",
                 "Leaves yellow and dry early"],
                "Warmer than yellow rust: 15–25 °C with dew.",
                ["Distinguish from yellow rust before acting — the varieties differ",
                 "Scout the flag leaf: protecting it protects the yield"],
            ),
            _disease(
                "wheat_powdery_mildew", "Powdery mildew",
                "Blumeria graminis f. sp. tritici",
                "white", "coating",
                ["White to greyish powdery growth on the upper leaf surface",
                 "Coating wipes off, leaving yellowed tissue beneath",
                 "Worst in the shaded lower canopy"],
                "Cool, cloudy, humid weather in a dense, heavily fertilised crop.",
                ["Avoid excess nitrogen and over-dense sowing",
                 "Check the lower canopy first — it starts in the shade"],
            ),
            _disease(
                "wheat_loose_smut", "Loose smut",
                "Ustilago segetum var. tritici",
                "brown", "blotch",
                ["Ears replaced by a mass of black powdery spores",
                 "Only the bare rachis remains once the spores blow away",
                 "Scattered affected tillers throughout the field"],
                "Seed-borne — the infection came in with the seed, not the weather.",
                ["Nothing helps this season; the fix is seed treatment next season",
                 "Rogue and bag affected ears before they shed spores"],
            ),
        ],
    },
    "gram": {
        "id": "gram",
        "name": "Chickpea (Gram)",
        "local_name": "Chana / चना",
        "season": "rabi",
        "note": "MP is the largest chickpea-producing state; mostly rainfed on "
                "residual moisture in black cotton soil.",
        "diseases": [
            _disease(
                "gram_wilt", "Fusarium wilt",
                "Fusarium oxysporum f. sp. ciceris",
                "yellow", "wilt",
                ["Sudden drooping of leaves and petioles while still green",
                 "Plants die in patches, often along the row",
                 "Split stem shows internal browning"],
                "Warm soil, soil-borne inoculum from a close chickpea rotation.",
                ["Map the patches — wilt sickness follows the soil, so the map "
                 "is worth keeping for next season",
                 "Rotate out of chickpea for 2–3 years in affected patches",
                 "Sow wilt-resistant varieties (JG-series)"],
            ),
            _disease(
                "gram_ascochyta_blight", "Ascochyta blight",
                "Ascochyta rabiei",
                "brown", "spots",
                ["Circular brown lesions with dark concentric rings on leaves and pods",
                 "Stem girdling that breaks the plant over",
                 "Rapid spread down the row after rain"],
                "Cool, cloudy, wet weather during the vegetative stage.",
                ["Act fast after unseasonal rain — it moves in days",
                 "Use clean seed and destroy infected crop debris"],
            ),
            _disease(
                "gram_botrytis_grey_mould", "Botrytis grey mould",
                "Botrytis cinerea",
                "grey", "coating",
                ["Grey fuzzy mould on flowers, pods and the growing tip",
                 "Flower drop and empty pods",
                 "Worst inside a thick canopy"],
                "Cloudy, humid weather at flowering in a dense crop.",
                ["Open the canopy — spacing is the main cultural control",
                 "Flowering is the critical window to protect"],
            ),
            _disease(
                "gram_pod_borer", "Pod borer (Helicoverpa) damage",
                "Helicoverpa armigera (insect pest)",
                "brown", "chewed",
                ["Neat round holes bored into pods, with the larva half inside",
                 "Chewed leaf margins and frass on the plant",
                 "Empty, hollowed pods"],
                "The dominant chickpea pest across MP; peaks at podding.",
                ["Pheromone traps to time the action, and bird perches in the field",
                 "Act at the larval stage — a bored pod is already lost"],
            ),
        ],
    },
    "maize": {
        "id": "maize",
        "name": "Maize",
        "local_name": "Makka / मक्का",
        "season": "kharif",
        "diseases": [
            _disease(
                "maize_turcicum_blight", "Turcicum leaf blight",
                "Exserohilum turcicum",
                "brown", "blotch",
                ["Long cigar-shaped grey-green to tan lesions running with the veins",
                 "Lesions merge until whole leaves dry",
                 "Starts on the lower leaves"],
                "Moderate temperature with heavy dew and a humid canopy.",
                ["Rotate and plough down infected stubble",
                 "Protect the leaves above the cob — those carry the grain fill"],
            ),
            # Added because the trained leaf model has a class for it. A
            # disease the CNN can name but the knowledge base cannot describe
            # is a dead end: the scan resolves to "general stress" and the
            # farmer is told less than the model actually knows.
            _disease(
                "maize_gray_leaf_spot", "Grey leaf spot",
                "Cercospora zeae-maydis",
                "grey", "streak",
                ["Narrow rectangular grey to tan lesions boxed in by the veins",
                 "Straight-sided, unlike the cigar shape of turcicum blight",
                 "Worst in continuous maize under minimum tillage"],
                "Long humid nights with heavy dew, in a dense canopy.",
                ["Rotate out of maize — the fungus overwinters on stubble",
                 "Bury residue rather than leaving it on the surface",
                 "Protect the ear leaf and above; those fill the grain"],
            ),
            _disease(
                "maize_common_rust", "Common rust",
                "Puccinia sorghi",
                "orange", "spots",
                ["Cinnamon-brown powdery pustules on both leaf surfaces",
                 "Pustules scattered, not in stripes"],
                "Cool, humid weather.",
                ["Usually tolerable; act only if it reaches the upper canopy early"],
            ),
            _disease(
                "maize_fall_armyworm", "Fall armyworm damage",
                "Spodoptera frugiperda (insect pest)",
                "brown", "chewed",
                ["Ragged window-pane feeding on young leaves",
                 "Moist sawdust-like frass in the whorl",
                 "Whorl and cob damage in older plants"],
                "Warm weather; now established across Indian maize.",
                ["Check the whorl — that is where the larva sits",
                 "Hand-pick and destroy egg masses in small holdings",
                 "Time any spray to early instars in the whorl"],
            ),
        ],
    },
    "mustard": {
        "id": "mustard",
        "name": "Mustard",
        "local_name": "Sarson / सरसों",
        "season": "rabi",
        "diseases": [
            _disease(
                "mustard_alternaria_blight", "Alternaria blight",
                "Alternaria brassicae",
                "brown", "spots",
                ["Round dark brown spots with concentric rings on leaves and pods",
                 "Spots merge into large dried areas",
                 "Pods shrivel and seed fills poorly"],
                "Humid weather with temperatures around 20–25 °C.",
                ["Sow on time — late-sown mustard takes the worst of it",
                 "Remove crop residue that carries the fungus over"],
            ),
            _disease(
                "mustard_white_rust", "White rust",
                "Albugo candida",
                "white", "coating",
                ["Raised white blister-like pustules on the underside of leaves",
                 "Swollen, deformed flower stalks ('stag head')"],
                "Cool, moist conditions with long leaf wetness.",
                ["Rogue stag-head shoots before the blisters burst",
                 "Rotate away from crucifers"],
            ),
            _disease(
                "mustard_aphid", "Mustard aphid infestation",
                "Lipaphis erysimi (insect pest)",
                "grey", "coating",
                ["Dense grey-green aphid colonies on the flowering shoot",
                 "Sticky honeydew and sooty mould below the colony",
                 "Curled, stunted flowering tops"],
                "Cool, cloudy January weather — the classic MP mustard pest peak.",
                ["Scout the flowering shoots, which is where colonies build",
                 "Protect the pollinators: treat only when the threshold is crossed"],
            ),
        ],
    },
    "cotton": {
        "id": "cotton",
        "name": "Cotton",
        "local_name": "Kapas / कपास",
        "season": "kharif",
        "note": "Grown in the Nimar valley — Khargone, Khandwa, Barwani.",
        "diseases": [
            _disease(
                "cotton_leaf_curl", "Cotton leaf curl virus",
                "Begomovirus, spread by whitefly",
                "green", "mosaic",
                ["Upward curling and thickening of leaves",
                 "Vein swelling and leaf-like enations on the underside",
                 "Stunted plants in patches"],
                "High whitefly pressure in hot dry weather.",
                ["Manage the whitefly vector; the virus itself cannot be cured",
                 "Rogue early infected plants"],
            ),
            _disease(
                "cotton_bacterial_blight", "Bacterial blight (angular leaf spot)",
                "Xanthomonas citri pv. malvacearum",
                "brown", "spots",
                ["Angular water-soaked spots bounded by the leaf veins",
                 "Black arm lesions on stems, boll rot",
                 "Spreads after wind-driven rain"],
                "Storms and prolonged leaf wetness.",
                ["Acid-delinted, treated seed is the main control",
                 "Avoid working the field wet — that is how it moves"],
            ),
            _disease(
                "cotton_alternaria_spot", "Alternaria leaf spot",
                "Alternaria macrospora",
                "brown", "spots",
                ["Brown spots with concentric rings and a purple margin",
                 "Heavy defoliation in a stressed crop"],
                "Humidity plus potassium deficiency or general crop stress.",
                ["Correct potassium status — this often follows nutrient stress"],
            ),
        ],
    },
    "pigeonpea": {
        "id": "pigeonpea",
        "name": "Pigeonpea (Tur / Arhar)",
        "local_name": "Tur / तुअर",
        "season": "kharif",
        "diseases": [
            _disease(
                "pigeonpea_wilt", "Fusarium wilt",
                "Fusarium udum",
                "yellow", "wilt",
                ["Plants wilt and dry, often one branch at a time",
                 "Purple-brown band running up the stem from the base",
                 "Patches that reappear in the same spot each year"],
                "Soil-borne; builds under a close pigeonpea rotation.",
                ["Map the patch and rotate it out of pigeonpea",
                 "Sow wilt-resistant varieties"],
            ),
            _disease(
                "pigeonpea_sterility_mosaic", "Sterility mosaic",
                "Pigeonpea sterility mosaic virus, spread by eriophyid mite",
                "yellow", "mosaic",
                ["Bushy, pale, small-leaved plants that stay green but never flower",
                 "Light and dark green mosaic on leaves",
                 "Complete sterility — no pods at all"],
                "Mite-transmitted; spreads from field edges and volunteer plants.",
                ["Rogue the bushy green non-flowering plants — they are the source",
                 "Remove volunteer and ratoon pigeonpea"],
                "A green, healthy-looking canopy with no pods: high NDVI, zero "
                "yield, which is exactly the case the imagery alone will miss.",
            ),
        ],
    },
}

# Generic fallbacks when the crop is unknown or nothing matches well.
GENERIC_CONDITIONS = {
    "healthy": {
        "id": "healthy",
        "name": "No disease detected",
        "pathogen": "",
        "signature": {"colour": "green", "pattern": "none"},
        "symptoms": ["Canopy is uniformly green with no visible lesions"],
        "favours": "",
        "management": ["Keep monitoring — re-fly in 7–10 days to catch change early"],
        "severity_note": "",
    },
    "general_stress": {
        "id": "general_stress",
        "name": "Crop stress (cause unclear)",
        "pathogen": "",
        "signature": {"colour": "yellow", "pattern": "blotch"},
        "symptoms": ["Discoloured or thin canopy without a clear disease pattern"],
        "favours": "Water, nutrient or root problems as often as disease.",
        "management": [
            "Ground-truth before treating — this pattern is not diagnostic",
            "Check soil moisture and nutrition first; they explain most of it",
        ],
        "severity_note": "",
    },
}


# ── Lookups ──────────────────────────────────────────────────────────────────

def crop_ids() -> List[str]:
    return list(CROPS.keys())


def list_crops() -> List[Dict[str, Any]]:
    """Catalogue for the app's crop picker."""
    return [
        {
            "id": crop["id"],
            "name": crop["name"],
            "local_name": crop.get("local_name", ""),
            "season": crop.get("season", ""),
            "note": crop.get("note", ""),
            "disease_count": len(crop["diseases"]),
        }
        for crop in CROPS.values()
    ]


def get_crop(crop_id: Optional[str]) -> Optional[Dict[str, Any]]:
    if not crop_id:
        return None
    return CROPS.get(str(crop_id).strip().lower())


def diseases_for(crop_id: Optional[str]) -> List[Dict[str, Any]]:
    crop = get_crop(crop_id)
    return list(crop["diseases"]) if crop else []


def get_disease(disease_id: Optional[str]) -> Dict[str, Any]:
    """A disease entry by id, falling back to the generic stress entry."""
    key = str(disease_id or "").strip().lower()
    if key in GENERIC_CONDITIONS:
        return GENERIC_CONDITIONS[key]
    for crop in CROPS.values():
        for disease in crop["diseases"]:
            if disease["id"] == key:
                return disease
    return GENERIC_CONDITIONS["general_stress"]


def crop_of_disease(disease_id: str) -> Optional[str]:
    key = str(disease_id or "").strip().lower()
    for crop_id, crop in CROPS.items():
        if any(d["id"] == key for d in crop["diseases"]):
            return crop_id
    return None


def all_disease_ids() -> List[str]:
    ids = list(GENERIC_CONDITIONS.keys())
    for crop in CROPS.values():
        ids.extend(d["id"] for d in crop["diseases"])
    return ids
