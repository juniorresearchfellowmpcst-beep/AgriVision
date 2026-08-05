"""Weed knowledge base for Madhya Pradesh cropping systems.

The weeds that actually cost yield here are few and well known, and they are
crop-specific: *Phalaris minor* is the wheat problem, *Echinochloa* is the
paddy problem, and *Cyperus rotundus* is everybody's problem. So the detector
reports a weed *pressure* from the imagery and then uses the crop to say which
weeds that pressure most likely is — which is the answer an operator can act
on, in a way that "weeds: 12%" is not.

Three morphology classes matter because they decide the herbicide group:

    grass      narrow upright leaves, parallel veins (Phalaris, Echinochloa)
    sedge      triangular stem, glossy — tolerant of most grass herbicides
    broadleaf  wide leaves, netted veins (Chenopodium, Parthenium)

Herbicide actives are named as the *group* a farmer would ask their dealer
about; rates and timing belong to the label and the local KVK, not here.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

WEED_TYPES = ("grass", "sedge", "broadleaf")


def _weed(
    id: str,
    name: str,
    local_name: str,
    weed_type: str,
    crops: List[str],
    why: str,
    identify: List[str],
    control: List[str],
) -> Dict[str, Any]:
    return {
        "id": id,
        "name": name,
        "local_name": local_name,
        "type": weed_type,
        "crops": crops,
        "why_it_matters": why,
        "identify": identify,
        "control": control,
    }


WEEDS: Dict[str, Dict[str, Any]] = {
    "phalaris_minor": _weed(
        "phalaris_minor", "Littleseed canarygrass", "Gehun ka mama / गेहूँ का मामा",
        "grass", ["wheat"],
        "The single biggest weed problem in irrigated wheat, and widely "
        "resistant to isoproturon after decades of repeat use.",
        ["Looks almost exactly like young wheat — that is the trouble",
         "Leaf sheath is smooth and the ligule is longer than wheat's",
         "Leaves twist anti-clockwise; wheat twists clockwise"],
        ["Rotate herbicide groups every season — resistance here is real",
         "Clodinafop / sulfosulfuron / pinoxaden groups are the usual post-emergence choices",
         "Delay first irrigation slightly to favour the crop over the weed"],
    ),
    "chenopodium_album": _weed(
        "chenopodium_album", "Lambsquarters", "Bathua / बथुआ",
        "broadleaf", ["wheat", "gram", "mustard"],
        "Heavy early competitor in rabi crops; also a host for aphids.",
        ["Soft, mealy-white coating on young leaves and stem tips",
         "Diamond-shaped leaves with toothed margins"],
        ["2,4-D or metsulfuron groups where the crop tolerates them",
         "One hand weeding at 30–35 days removes most of the competition"],
    ),
    "avena_fatua": _weed(
        "avena_fatua", "Wild oat", "Jangli jai / जंगली जई",
        "grass", ["wheat"],
        "Tall grass that overtops wheat and shatters seed before harvest.",
        ["Taller and coarser than the crop, with a drooping open panicle",
         "Twisted, dark awn on the seed"],
        ["Same grass-herbicide groups as Phalaris; rogue survivors before seed set",
         "Clean seed is the main prevention — it travels with the grain"],
    ),
    "echinochloa": _weed(
        "echinochloa", "Barnyard grass", "Sawank / सांवक",
        "grass", ["rice", "soybean", "maize"],
        "The dominant paddy weed; mimics rice seedlings closely enough to "
        "survive the first hand weeding.",
        ["No ligule at the leaf base — rice has one; that is the field test",
         "Reddish-purple tinge at the base of older plants",
         "Grows faster than the crop after transplanting"],
        ["Bispyribac-sodium / cyhalofop groups in transplanted paddy",
         "Keep 3–5 cm standing water: it suppresses germination",
         "Weed within the first 30 days — after that the yield is already lost"],
    ),
    "cyperus_rotundus": _weed(
        "cyperus_rotundus", "Purple nutsedge", "Motha / मोथा",
        "sedge", ["rice", "soybean", "maize", "cotton", "wheat"],
        "Perennial from tubers, so cutting or ploughing spreads it; tolerant "
        "of most grass and broadleaf herbicides.",
        ["Triangular stem — roll it between your fingers to check",
         "Dark glossy leaves in threes, reddish-brown flower head",
         "Comes back from tubers after every weeding"],
        ["Target the tuber bank, not the shoots — repeated shoot removal only",
         "Halosulfuron group where the crop allows it",
         "Summer deep ploughing to expose tubers to the sun"],
    ),
    "commelina_benghalensis": _weed(
        "commelina_benghalensis", "Tropical spiderwort", "Kanakauwa / कनकौआ",
        "broadleaf", ["soybean", "maize", "cotton"],
        "Succulent stems root at the nodes, so it regrows from fragments left "
        "behind by mechanical weeding.",
        ["Fleshy, jointed stems with blue three-petalled flowers",
         "Roots wherever a node touches wet soil"],
        ["Remove whole plants — fragments re-root",
         "Hard to kill once flowering; act early post-emergence"],
    ),
    "parthenium": _weed(
        "parthenium", "Congress grass", "Gajar ghas / गाजर घास",
        "broadleaf", ["soybean", "maize", "cotton", "wheat"],
        "Aggressive invader of field edges and fallows; also a serious human "
        "allergen for the people working the field.",
        ["Deeply cut carrot-like leaves and small white flower heads",
         "Dominates bunds, roadsides and any bare patch"],
        ["Uproot before flowering — and wear gloves; it causes dermatitis",
         "Never leave field edges bare; a competitive cover keeps it out",
         "The Mexican beetle Zygogramma bicolorata is used as a biocontrol"],
    ),
    "digera_arvensis": _weed(
        "digera_arvensis", "False amaranth", "Lehsua / लहसुआ",
        "broadleaf", ["soybean", "maize"],
        "Fast early growth in kharif that shades out young soybean.",
        ["Slender pinkish flowering spikes",
         "Soft, alternate oval leaves on a reddish stem"],
        ["Imazethapyr group in soybean, applied early post-emergence",
         "One inter-row cultivation at 20–25 days is usually enough"],
    ),
    "cynodon_dactylon": _weed(
        "cynodon_dactylon", "Bermuda grass", "Doob / दूब",
        "grass", ["wheat", "soybean", "cotton", "maize"],
        "Perennial with creeping stolons and rhizomes; the classic bund and "
        "headland grass that creeps into the crop.",
        ["Flat creeping runners rooting at every node",
         "Finger-like flower spikes radiating from one point"],
        ["Cultivation alone spreads it — remove the rhizomes",
         "Treat field margins, which is where it moves in from"],
    ),
    "melilotus_indica": _weed(
        "melilotus_indica", "Indian sweetclover", "Senji / सेंजी",
        "broadleaf", ["wheat", "gram", "mustard"],
        "Common in irrigated rabi fields; taints wheat grain quality if it "
        "goes through the thresher.",
        ["Clover-like leaves in threes with a sweet smell when crushed",
         "Small yellow flowers on a slender spike"],
        ["Remove before flowering to prevent seed return",
         "Broadleaf herbicide groups registered for the crop"],
    ),
}

# Which weeds to name first for a given crop — the pressure the imagery sees
# is generic, but the likely culprits are not.
CROP_WEEDS: Dict[str, List[str]] = {
    "wheat": ["phalaris_minor", "chenopodium_album", "avena_fatua",
              "melilotus_indica", "cynodon_dactylon"],
    "rice": ["echinochloa", "cyperus_rotundus"],
    "soybean": ["echinochloa", "digera_arvensis", "commelina_benghalensis",
                "cyperus_rotundus", "parthenium"],
    "gram": ["chenopodium_album", "melilotus_indica"],
    "maize": ["echinochloa", "cyperus_rotundus", "commelina_benghalensis",
              "digera_arvensis"],
    "mustard": ["chenopodium_album", "melilotus_indica"],
    "cotton": ["cyperus_rotundus", "commelina_benghalensis", "parthenium"],
    "pigeonpea": ["cyperus_rotundus", "parthenium", "digera_arvensis"],
}

# Weed cover as a share of the visible ground, and what it means for action.
PRESSURE_BANDS = [
    (0.02, "none", "Effectively clean — nothing worth acting on."),
    (0.08, "low", "Scattered weeds. Spot-weed rather than treating the block."),
    (0.20, "moderate", "Enough to cost yield if the crop is still young. "
                       "Plan a weeding or a banded herbicide pass."),
    (1.01, "high", "Heavy infestation competing with the crop now. Treat "
                   "before the critical weed-free period closes."),
]


def get_weed(weed_id: Optional[str]) -> Optional[Dict[str, Any]]:
    if not weed_id:
        return None
    return WEEDS.get(str(weed_id).strip().lower())


def list_weeds(crop_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """Weed catalogue, narrowed to one crop's usual suspects when given."""
    if crop_id:
        ids = CROP_WEEDS.get(str(crop_id).strip().lower(), [])
        return [WEEDS[i] for i in ids if i in WEEDS]
    return list(WEEDS.values())


def likely_weeds(crop_id: Optional[str], limit: int = 3) -> List[Dict[str, Any]]:
    """The most probable weeds for a crop, worst first, for the scan result."""
    return list_weeds(crop_id)[:limit]


def pressure_for(coverage: float) -> Dict[str, Any]:
    """Turn a weed-cover fraction into a level plus what to do about it."""
    value = max(0.0, float(coverage or 0.0))
    for threshold, level, advice in PRESSURE_BANDS:
        if value < threshold:
            return {
                "level": level,
                "coverage": round(value, 4),
                "percent": int(round(value * 100)),
                "advice": advice,
            }
    band = PRESSURE_BANDS[-1]
    return {
        "level": band[1],
        "coverage": round(value, 4),
        "percent": int(round(value * 100)),
        "advice": band[2],
    }


def all_weed_ids() -> List[str]:
    return list(WEEDS.keys())
