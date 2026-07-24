"""Curated knowledge base of common crop-leaf conditions and their remedies.

This is the "give the solution" half of the disease-identification feature. The
image analysis in :mod:`app.ai.disease_detector` classifies a leaf photo into one
of the keys below; this module turns that key into farmer-readable symptoms,
likely causes, and an actionable treatment / prevention plan.

The advice here is deliberately general-purpose (organic + chemical + cultural
options) because a single RGB photo can only reveal a *visual category* of
stress, not the exact pathogen or its strain. The frontend surfaces a disclaimer
to that effect. Always follow local agricultural-extension guidance and product
labels for dosages.
"""

from __future__ import annotations

from typing import Any, Dict, List

# Each solution item is grouped by `type` so the app can render them under
# labelled sections (cultural / organic / chemical / monitoring).
Solution = Dict[str, str]

# The canonical set of conditions the detector can report. Keys are stable ids
# used across the backend and app; do not rename without updating both sides.
KNOWLEDGE_BASE: Dict[str, Dict[str, Any]] = {
    "healthy": {
        "name": "Healthy plant",
        "also_known_as": "No disease detected",
        "description": (
            "The leaf is predominantly uniform green with no significant "
            "yellowing, spotting, or dead tissue. No visual signs of disease "
            "or nutrient stress were found."
        ),
        "symptoms": [
            "Even, vigorous green colour across the leaf blade.",
            "No spots, lesions, powder, or wilting visible.",
        ],
        "causes": [
            "Good growing conditions — adequate water, nutrients and light.",
        ],
        "solutions": [
            {
                "type": "monitoring",
                "title": "Keep scouting",
                "detail": "Continue weekly field checks so any early outbreak "
                "is caught before it spreads.",
            },
            {
                "type": "cultural",
                "title": "Maintain routine",
                "detail": "Keep up balanced irrigation and fertilisation; avoid "
                "over-watering which invites fungal disease.",
            },
        ],
        "prevention": [
            "Rotate crops each season to break pest and disease cycles.",
            "Keep the field free of weeds and old crop debris.",
        ],
    },
    "nutrient_deficiency": {
        "name": "Nutrient deficiency / chlorosis",
        "also_known_as": "Yellowing (chlorosis)",
        "description": (
            "Widespread yellowing of the leaf tissue, often between the veins, "
            "points to a nutrient shortfall (commonly nitrogen, magnesium or "
            "iron) rather than an infectious disease. Waterlogging or root "
            "damage can produce the same look."
        ),
        "symptoms": [
            "Pale-green to yellow leaves, frequently starting on older leaves.",
            "Veins may stay green while the tissue between them yellows.",
            "Overall loss of vigour and slower growth.",
        ],
        "causes": [
            "Low soil nitrogen, magnesium, iron or other micronutrients.",
            "Poor drainage / waterlogging limiting root uptake.",
            "Soil pH too high or too low, locking up nutrients.",
        ],
        "solutions": [
            {
                "type": "cultural",
                "title": "Confirm with a soil test",
                "detail": "Test soil pH and nutrient levels before feeding so "
                "you correct the right deficiency.",
            },
            {
                "type": "organic",
                "title": "Add organic matter",
                "detail": "Work in well-rotted compost or manure, and use a "
                "foliar seaweed spray for a quick micronutrient boost.",
            },
            {
                "type": "chemical",
                "title": "Targeted fertiliser",
                "detail": "Apply a balanced NPK feed; for interveinal yellowing "
                "use magnesium sulphate (Epsom salt) or a chelated-iron spray.",
            },
            {
                "type": "cultural",
                "title": "Fix drainage",
                "detail": "Improve field drainage and avoid over-watering so "
                "roots can take up nutrients again.",
            },
        ],
        "prevention": [
            "Feed with a balanced fertiliser programme through the season.",
            "Keep soil pH in the crop's ideal range.",
            "Maintain good soil structure with organic matter.",
        ],
    },
    "fungal_leaf_spot": {
        "name": "Fungal / bacterial leaf spot",
        "also_known_as": "Leaf spot, Cercospora / Septoria-type spotting",
        "description": (
            "Numerous distinct spots or lesions scattered across the leaf. "
            "These are typically caused by fungal or bacterial pathogens that "
            "thrive in warm, wet, humid conditions and spread by rain splash."
        ),
        "symptoms": [
            "Small round-to-angular brown, black or tan spots, sometimes with "
            "a yellow halo.",
            "Spots may merge; centres can dry out and fall away ('shot-hole').",
            "Heavy infection causes leaves to yellow and drop early.",
        ],
        "causes": [
            "Fungal or bacterial pathogens favoured by high humidity and leaf "
            "wetness.",
            "Overhead irrigation and rain splash spreading spores.",
            "Crowded planting with poor air circulation.",
        ],
        "solutions": [
            {
                "type": "cultural",
                "title": "Remove infected leaves",
                "detail": "Pick off and destroy spotted leaves (do not compost) "
                "to reduce the source of spores.",
            },
            {
                "type": "cultural",
                "title": "Keep foliage dry",
                "detail": "Water at the base in the morning, not overhead, and "
                "space/prune plants for better airflow.",
            },
            {
                "type": "organic",
                "title": "Organic sprays",
                "detail": "Apply a copper-based or neem-oil fungicide early, "
                "repeating per label after rain.",
            },
            {
                "type": "chemical",
                "title": "Fungicide programme",
                "detail": "For persistent spread use a labelled protectant "
                "fungicide (e.g. chlorothalonil or mancozeb); rotate active "
                "ingredients to avoid resistance.",
            },
        ],
        "prevention": [
            "Use certified disease-free seed and resistant varieties.",
            "Rotate crops and clear infected debris after harvest.",
            "Avoid working among plants while the foliage is wet.",
        ],
    },
    "blight": {
        "name": "Blight (early / late blight type)",
        "also_known_as": "Leaf blight, necrosis",
        "description": (
            "Large irregular patches of dead (brown/black) tissue spreading "
            "across the leaf, often quickly. Blights — such as tomato/potato "
            "early and late blight — can collapse foliage within days in cool, "
            "wet weather."
        ),
        "symptoms": [
            "Large brown-to-black blotches, sometimes with concentric rings "
            "(early blight) or a greasy grey margin (late blight).",
            "Rapid browning and collapse of large leaf areas.",
            "May spread to stems and fruit in severe cases.",
        ],
        "causes": [
            "Aggressive fungal / oomycete pathogens (e.g. Alternaria, "
            "Phytophthora) favoured by cool, wet, humid weather.",
            "Prolonged leaf wetness and dense canopy.",
        ],
        "solutions": [
            {
                "type": "cultural",
                "title": "Act fast — remove & isolate",
                "detail": "Cut out and destroy affected foliage immediately to "
                "slow the spread; do not leave debris in the field.",
            },
            {
                "type": "chemical",
                "title": "Protectant + systemic fungicide",
                "detail": "Apply a labelled blight fungicide (e.g. mancozeb, "
                "chlorothalonil, or a metalaxyl product for late blight) and "
                "repeat on schedule during wet spells.",
            },
            {
                "type": "organic",
                "title": "Copper sprays",
                "detail": "Copper-based fungicides give partial protection when "
                "applied early and repeated after rain.",
            },
            {
                "type": "cultural",
                "title": "Improve airflow & drainage",
                "detail": "Stake/prune for airflow, water at the base, and avoid "
                "waterlogged soil.",
            },
        ],
        "prevention": [
            "Plant resistant varieties and use clean, certified seed/tubers.",
            "Rotate away from the same family for 2-3 seasons.",
            "Scout during cool wet weather and spray preventatively if blight "
            "is forecast.",
        ],
    },
    "powdery_mildew": {
        "name": "Powdery mildew",
        "also_known_as": "White mould coating",
        "description": (
            "A white-to-grey powdery coating on the leaf surface. Unlike most "
            "diseases, powdery mildew is worst in warm days with cool, humid "
            "nights and does not need free water on the leaf to infect."
        ),
        "symptoms": [
            "Dusty white or grey patches on the upper leaf surface.",
            "Leaves may curl, yellow and dry out under the coating.",
            "Reduced photosynthesis and stunted growth.",
        ],
        "causes": [
            "Powdery-mildew fungi favoured by warm days and humid nights.",
            "Shade and poor air circulation.",
            "Excess nitrogen producing soft, susceptible new growth.",
        ],
        "solutions": [
            {
                "type": "organic",
                "title": "Potassium-bicarbonate or milk spray",
                "detail": "Spray potassium bicarbonate, or a diluted milk / neem "
                "solution, on affected leaves at first sign; repeat weekly.",
            },
            {
                "type": "cultural",
                "title": "Prune for airflow",
                "detail": "Thin dense growth and remove the worst leaves to let "
                "air and light in.",
            },
            {
                "type": "chemical",
                "title": "Sulphur / labelled fungicide",
                "detail": "Use a sulphur-based or labelled mildew fungicide, "
                "avoiding application in high heat to prevent leaf burn.",
            },
            {
                "type": "cultural",
                "title": "Ease off nitrogen",
                "detail": "Avoid heavy nitrogen feeding, which fuels the soft "
                "growth mildew prefers.",
            },
        ],
        "prevention": [
            "Grow mildew-resistant varieties where available.",
            "Space plants for good airflow and full sun.",
            "Avoid overhead watering late in the day.",
        ],
    },
    "pest_damage": {
        "name": "Pest / physical damage",
        "also_known_as": "Chewing damage, holes",
        "description": (
            "Irregular holes, ragged edges or missing tissue suggest feeding by "
            "insects (caterpillars, beetles, grasshoppers) or mechanical / "
            "weather damage rather than an infectious disease."
        ),
        "symptoms": [
            "Holes, notches or ragged, chewed leaf margins.",
            "Possible frass (droppings), webbing or visible insects.",
            "Damage often clustered where pests are feeding.",
        ],
        "causes": [
            "Chewing insects such as caterpillars, beetles or grasshoppers.",
            "Hail, wind or handling damage.",
        ],
        "solutions": [
            {
                "type": "monitoring",
                "title": "Scout and identify the pest",
                "detail": "Check undersides of leaves and the soil line to find "
                "and identify the culprit before treating.",
            },
            {
                "type": "organic",
                "title": "Hand-pick & bio-controls",
                "detail": "Remove pests by hand where feasible; use neem oil or "
                "Bacillus thuringiensis (Bt) for caterpillars.",
            },
            {
                "type": "cultural",
                "title": "Barriers & beneficials",
                "detail": "Use row covers on young plants and encourage natural "
                "predators (ladybirds, lacewings, birds).",
            },
            {
                "type": "chemical",
                "title": "Targeted insecticide",
                "detail": "If damage is severe, apply a labelled insecticide "
                "matched to the pest, following pre-harvest intervals.",
            },
        ],
        "prevention": [
            "Scout regularly so infestations are caught early.",
            "Keep the field weed-free to remove pest shelter.",
            "Encourage biodiversity and beneficial insects.",
        ],
    },
    "general_stress": {
        "name": "General leaf stress (inconclusive)",
        "also_known_as": "Unspecified discolouration",
        "description": (
            "The leaf shows discolouration or damage, but the pattern does not "
            "clearly match a single condition from a photo alone. This can be "
            "early disease, environmental stress (heat, drought, cold), spray "
            "injury, or a mix."
        ),
        "symptoms": [
            "Patchy discolouration, browning or mottling without a clear "
            "single pattern.",
            "Possible wilting or scorching at leaf edges.",
        ],
        "causes": [
            "Environmental stress: drought, heat, cold, or salt.",
            "Early or mixed disease not yet distinctive.",
            "Chemical / spray injury.",
        ],
        "solutions": [
            {
                "type": "monitoring",
                "title": "Re-check in a few days",
                "detail": "Photograph the same plants again in 3-5 days; a "
                "developing pattern makes diagnosis clearer.",
            },
            {
                "type": "cultural",
                "title": "Stabilise growing conditions",
                "detail": "Even out watering, provide shade in heat, and avoid "
                "fertiliser or spray applications during stress.",
            },
            {
                "type": "monitoring",
                "title": "Get an expert opinion",
                "detail": "Take a sample to a local agricultural-extension "
                "office or agronomist for a definitive diagnosis.",
            },
        ],
        "prevention": [
            "Keep growing conditions steady and avoid stress at key stages.",
            "Follow label rates carefully when spraying.",
            "Scout regularly to catch problems while they are still minor.",
        ],
    },
}


def get_condition(condition_id: str) -> Dict[str, Any]:
    """Return the knowledge-base entry for ``condition_id``.

    Falls back to the "general_stress" entry for any unknown id so callers
    always get a usable, farmer-readable payload.
    """
    entry = KNOWLEDGE_BASE.get(condition_id) or KNOWLEDGE_BASE["general_stress"]
    # Return a shallow copy so callers can safely enrich it (add confidence,
    # severity, etc.) without mutating the shared table.
    return {"id": condition_id if condition_id in KNOWLEDGE_BASE else "general_stress", **entry}


def all_condition_ids() -> List[str]:
    return list(KNOWLEDGE_BASE.keys())
