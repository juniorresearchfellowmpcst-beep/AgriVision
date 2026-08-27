"""What to actually put in the tank.

:mod:`app.ai.crop_kb` says *what is wrong* and gives management advice in
words ("a protective fungicide at pod initiation"). That is the right level for
an agronomy note and the wrong level for a drone that is about to be filled and
sent out: somebody has to decide which product, at what dose, in how much
water, and whether two detected problems can share one tank.

This module is that decision, written down. Every entry is standard
package-of-practices guidance for the Madhya Pradesh cropping system, and every
entry is *decision support* -- the label on the container and the local KVK
outrank anything here, which is why :data:`DISCLAIMER` rides on every response
and why doses are given as the label's range rather than a single number
invented for the sake of looking precise.

Three things this module deliberately does **not** do:

  * **It does not pick a brand.** Products are named by active ingredient and
    formulation, because that is what is on the label and what a dealer can
    match; brand names change district to district.
  * **It does not silently mix.** Two conditions found in the same block do not
    automatically become one tank. :func:`spray_plan` groups by what can share
    a tank and says plainly when a second pass is needed -- a fungicide and an
    alkaline-sensitive insecticide in the same load is a wasted flight.
  * **It does not promise a cure.** A virus (yellow mosaic, leaf curl, sterility
    mosaic) has no spray that treats it. Those entries target the *vector*
    instead and say so, because spraying a fungicide on a virus is the most
    expensive way to do nothing.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

# Shown wherever a product is named. Not decoration: a chemical recommendation
# derived from a camera is the start of a conversation with an agronomist.
DISCLAIMER = (
    "Decision support only. Confirm the diagnosis on the ground and follow the "
    "product label and local KVK advice for dose, crop stage and pre-harvest "
    "interval before spraying."
)

# What a product is for. Determines which detections can share a tank.
CATEGORIES = (
    "fungicide", "insecticide", "herbicide", "bactericide", "biological", "nutrient",
)

# Categories that can normally be tank-mixed with each other. Anything outside
# a shared group is planned as a separate pass.
TANK_GROUPS = {
    "fungicide": "protectant",
    "bactericide": "protectant",
    "nutrient": "protectant",
    "biological": "biological",
    "insecticide": "insecticide",
    "herbicide": "herbicide",
}

# Human labels for the tank groups, used in the app's spray plan card.
TANK_GROUP_NAMES = {
    "protectant": "Fungicide / bactericide tank",
    "biological": "Biological tank",
    "insecticide": "Insecticide tank",
    "herbicide": "Herbicide tank",
}


def _product(
    name: str,
    category: str,
    dose: str,
    water: str,
    timing: str,
    note: str = "",
    phi_days: Optional[int] = None,
    drone_ready: bool = True,
) -> Dict[str, Any]:
    """One sprayable recommendation.

    ``dose`` and ``water`` are per acre, because that is the unit an operator in
    MP works in and converting for them invites an order-of-magnitude error.
    ``drone_ready`` is False for anything that is not a spray at all (a seed
    treatment, a soil drench) -- the aircraft cannot deliver it, and the plan
    has to say so rather than loading the tank with something that cannot work.
    """
    return {
        "name": name,
        "category": category,
        "dose_per_acre": dose,
        "water_per_acre": water,
        "timing": timing,
        "note": note,
        "phi_days": phi_days,
        "drone_ready": drone_ready,
        "tank_group": TANK_GROUPS.get(category, "protectant"),
    }


def _treatment(
    summary: str,
    products: List[Dict[str, Any]],
    cultural: List[str],
    sprayable: bool = True,
    urgency: str = "routine",
) -> Dict[str, Any]:
    """The full answer for one condition.

    ``sprayable`` is the flag the drone flow keys on. A virus is not sprayable
    even though its *vector* is, and conflating the two is how a farmer ends up
    paying for a fungicide that was never going to help.
    """
    return {
        "summary": summary,
        "sprayable": sprayable,
        "urgency": urgency,          # routine | soon | urgent
        "products": products,
        "cultural": cultural,
        "disclaimer": DISCLAIMER,
    }


# -- Per-condition treatment -------------------------------------------------
#
# Keys match disease ids in app.ai.crop_kb, so a detection maps straight to a
# tank with no lookup table in between.

TREATMENTS: Dict[str, Dict[str, Any]] = {

    # -- soybean ----------------------------------------------------------
    "soybean_yellow_mosaic": _treatment(
        "The virus itself cannot be sprayed. Everything below targets the "
        "whitefly that carries it, which is the only part a tank can reach.",
        [
            _product(
                "Thiamethoxam 25% WG", "insecticide", "40 g", "150-200 L",
                "As soon as whitefly is seen on the underside of leaves",
                "Rotate to a different group next spray -- whitefly builds "
                "resistance quickly on repeat use.",
                phi_days=21,
            ),
            _product(
                "Diafenthiuron 50% WP", "insecticide", "240 g", "150-200 L",
                "Alternate spray where whitefly pressure stays high",
                phi_days=21,
            ),
        ],
        ["Rogue and remove infected plants -- they stay a source all season",
         "Do not spray a fungicide for this: it is a virus, not a fungus",
         "Choose a YMV-tolerant variety (JS 20-series) next season"],
        urgency="urgent",
    ),
    "soybean_charcoal_rot": _treatment(
        "Driven by moisture stress, so irrigation does more than any spray. "
        "Chemistry here is containment at best.",
        [
            _product(
                "Carbendazim 50% WP", "fungicide", "200 g", "150-200 L",
                "Early, on the advancing edge of a patch",
                "Soil-borne -- a foliar spray reaches very little of the "
                "pathogen. Treat this as containment, not control.",
                phi_days=30,
            ),
            _product(
                "Trichoderma viride 1% WP", "biological", "1 kg with FYM",
                "--", "Pre-sowing or with the first irrigation",
                "Soil application, not a drone spray.",
                drone_ready=False,
            ),
        ],
        ["Irrigate if at all possible -- the disease is a drought symptom",
         "Avoid dense stands on light soils",
         "Rotate away from soybean where patches recur"],
        urgency="soon",
    ),
    "soybean_anthracnose": _treatment(
        "A protective fungicide at pod initiation is the standard answer when "
        "wet weather persists.",
        [
            _product(
                "Tebuconazole 25.9% EC", "fungicide", "200 ml", "150-200 L",
                "At pod initiation; repeat after 15 days if wet weather holds",
                phi_days=30,
            ),
            _product(
                "Azoxystrobin 18.2% + Difenoconazole 11.4% SC", "fungicide",
                "200 ml", "150-200 L",
                "Alternate spray, to avoid leaning on one chemical group",
                phi_days=30,
            ),
        ],
        ["Improve airflow -- avoid over-dense sowing",
         "Use clean, treated seed next season"],
        urgency="soon",
    ),
    "soybean_rust": _treatment(
        "Rust moves up the canopy fast once it starts. Timing beats product "
        "choice here.",
        [
            _product(
                "Hexaconazole 5% EC", "fungicide", "400 ml", "200 L",
                "At the first pustules in the lower canopy",
                phi_days=30,
            ),
            _product(
                "Propiconazole 25% EC", "fungicide", "200 ml", "200 L",
                "Repeat after 12-15 days if the season stays humid",
                phi_days=30,
            ),
        ],
        ["Scout the lower canopy -- rust starts there and moves up",
         "Do not wait for the top of the canopy to show it"],
        urgency="urgent",
    ),
    "soybean_girdle_beetle": _treatment(
        "An insect, not a disease. The window is short: once the stem is "
        "girdled, that plant is lost.",
        [
            _product(
                "Thiacloprid 21.7% SC", "insecticide", "300 ml", "150-200 L",
                "At first sight of girdled shoots",
                phi_days=21,
            ),
            _product(
                "Chlorantraniliprole 18.5% SC", "insecticide", "60 ml", "150-200 L",
                "Alternate group where damage continues",
                phi_days=21,
            ),
        ],
        ["Cut and destroy girdled shoots below the lower ring",
         "Early sowing usually escapes the worst of it"],
        urgency="urgent",
    ),

    # -- rice -------------------------------------------------------------
    "rice_blast": _treatment(
        "Neck blast at panicle emergence costs far more than leaf blast. Plan "
        "the spray around that stage.",
        [
            _product(
                "Tricyclazole 75% WP", "fungicide", "120 g", "200 L",
                "At the first leaf lesions, and again at boot-leaf stage",
                phi_days=30,
            ),
            _product(
                "Isoprothiolane 40% EC", "fungicide", "300 ml", "200 L",
                "Alternate spray, especially where neck blast is the risk",
                phi_days=30,
            ),
        ],
        ["Stop topping up nitrogen -- excess N feeds blast directly",
         "Drain and re-flood rather than holding a constantly wet canopy"],
        urgency="urgent",
    ),
    "rice_bacterial_blight": _treatment(
        "Bacterial, so ordinary fungicides do nothing. Copper plus a "
        "streptomycin-class product is the standard combination.",
        [
            _product(
                "Copper oxychloride 50% WP", "bactericide", "500 g", "200 L",
                "At the first water-soaked streaks along the leaf margin",
                "Pair with streptocycline below; copper alone is weak here.",
                phi_days=15,
            ),
            _product(
                "Streptocycline (streptomycin sulphate + tetracycline)",
                "bactericide", "15 g", "200 L",
                "With the copper spray; repeat once after 10 days",
                "Restricted in some states -- check availability before "
                "planning the flight.",
                phi_days=15,
            ),
        ],
        ["Drain the field -- standing water carries it plant to plant",
         "Cut nitrogen; lush growth is what it runs through",
         "Never spray a fungicide for this -- it is a bacterium"],
        urgency="urgent",
    ),
    "rice_brown_spot": _treatment(
        "Usually a nutrition problem wearing a disease's clothes. Potash "
        "deficiency is the common driver in MP's lighter paddy soils.",
        [
            _product(
                "Mancozeb 75% WP", "fungicide", "600 g", "200 L",
                "At first spotting; repeat after 12-15 days",
                phi_days=20,
            ),
            _product(
                "Muriate of potash (1% foliar)", "nutrient", "1 kg", "100 L",
                "With or shortly after the fungicide spray",
                "Corrects the deficiency that let the spot in.",
            ),
        ],
        ["Correct potash and zinc -- this disease follows poor nutrition",
         "Use healthy, graded seed next season"],
        urgency="soon",
    ),
    "rice_sheath_blight": _treatment(
        "It climbs the sheath from the water line, so the spray has to reach "
        "the base of the canopy -- a high pass will miss it entirely.",
        [
            _product(
                "Validamycin 3% L", "fungicide", "500 ml", "200 L",
                "At the first sheath lesions near the water line",
                "Direct the spray low into the canopy, not over the top.",
                phi_days=20,
            ),
            _product(
                "Hexaconazole 5% EC", "fungicide", "400 ml", "200 L",
                "Alternate spray after 12-15 days",
                phi_days=30,
            ),
        ],
        ["Avoid dense planting -- it spreads by leaf-to-leaf contact",
         "Remove the weed hosts on the bunds"],
        urgency="urgent",
    ),

    # -- wheat ------------------------------------------------------------
    "wheat_yellow_rust": _treatment(
        "Yellow rust doubles fast in a cool, damp January. Spray on first "
        "sighting; waiting a week costs more than the chemical.",
        [
            _product(
                "Propiconazole 25% EC", "fungicide", "200 ml", "200 L",
                "At the first yellow stripes; repeat after 15 days if it spreads",
                phi_days=35,
            ),
            _product(
                "Tebuconazole 25.9% EC", "fungicide", "200 ml", "200 L",
                "Alternate group for the second spray",
                phi_days=35,
            ),
        ],
        ["Report a new focus -- rust races travel across districts",
         "Do not over-irrigate a crop that is already showing it"],
        urgency="urgent",
    ),
    "wheat_brown_rust": _treatment(
        "Same chemistry as yellow rust, usually later in the season and less "
        "explosive.",
        [
            _product(
                "Propiconazole 25% EC", "fungicide", "200 ml", "200 L",
                "At the first pustules on the leaf blade",
                phi_days=35,
            ),
        ],
        ["Late-sown crops take the worst of it -- adjust sowing next season"],
        urgency="soon",
    ),
    "wheat_powdery_mildew": _treatment(
        "Cheap to treat and easy to see. Sulphur handles it unless the crop is "
        "already under heat stress.",
        [
            _product(
                "Wettable sulphur 80% WP", "fungicide", "1 kg", "200 L",
                "At the first white coating on lower leaves",
                "Do not spray sulphur above about 32 C -- it scorches.",
                phi_days=15,
            ),
            _product(
                "Hexaconazole 5% EC", "fungicide", "400 ml", "200 L",
                "Where sulphur is ruled out by heat",
                phi_days=35,
            ),
        ],
        ["Thin, well-aired stands get much less of it"],
        urgency="routine",
    ),
    "wheat_loose_smut": _treatment(
        "Nothing sprayed this season will help -- the fungus is already inside "
        "the seed. This is a seed-treatment decision for next sowing.",
        [
            _product(
                "Carboxin 37.5% + Thiram 37.5% DS", "fungicide",
                "2.5-3 g per kg seed", "--",
                "As a seed treatment before next sowing",
                "Seed dressing, not a spray. The aircraft cannot deliver this.",
                drone_ready=False,
            ),
        ],
        ["Rogue smutted ears before they shed spores onto healthy heads",
         "Buy certified seed -- this travels in the seed lot"],
        sprayable=False,
        urgency="routine",
    ),

    # -- gram -------------------------------------------------------------
    "gram_wilt": _treatment(
        "Soil-borne and root-infecting. A foliar spray reaches almost none of "
        "it; the honest answer is seed treatment and rotation.",
        [
            _product(
                "Trichoderma viride 1% WP", "biological",
                "5 g per kg seed / 1 kg with FYM", "--",
                "Seed treatment at sowing, or soil application with FYM",
                "Not a drone spray.",
                drone_ready=False,
            ),
            _product(
                "Carbendazim 50% WP", "fungicide", "2 g per kg seed", "--",
                "Seed treatment before sowing",
                "Seed dressing, not a spray.",
                drone_ready=False,
            ),
        ],
        ["Rotate out of gram for 3-4 seasons where patches recur",
         "Sow wilt-resistant varieties (JG series) on affected land"],
        sprayable=False,
        urgency="routine",
    ),
    "gram_ascochyta_blight": _treatment(
        "Explodes in a wet, cloudy spell. Protect before the weather turns, "
        "not after.",
        [
            _product(
                "Mancozeb 75% WP", "fungicide", "600 g", "200 L",
                "Preventively when a wet, cloudy spell is forecast",
                phi_days=20,
            ),
            _product(
                "Chlorothalonil 75% WP", "fungicide", "400 g", "200 L",
                "Repeat after 10-12 days while the weather stays wet",
                phi_days=20,
            ),
        ],
        ["Do not walk or drive through a wet infected crop -- it spreads on contact",
         "Deep-plough infected residue after harvest"],
        urgency="urgent",
    ),
    "gram_botrytis_grey_mould": _treatment(
        "A dense canopy in a humid February is the whole cause. Airflow is the "
        "real control.",
        [
            _product(
                "Carbendazim 50% WP", "fungicide", "200 g", "200 L",
                "At flowering if the canopy is dense and the weather humid",
                phi_days=30,
            ),
            _product(
                "Thiophanate methyl 70% WP", "fungicide", "250 g", "200 L",
                "Alternate group for a second spray",
                phi_days=30,
            ),
        ],
        ["Wider rows and a lower seed rate on heavy land",
         "Avoid irrigating into a humid, still spell at flowering"],
        urgency="soon",
    ),
    "gram_pod_borer": _treatment(
        "Helicoverpa. The spray has to land while the larva is small and still "
        "outside the pod -- once it is inside, nothing reaches it.",
        [
            _product(
                "Chlorantraniliprole 18.5% SC", "insecticide", "60 ml", "200 L",
                "At early larval stage, before pods are bored",
                phi_days=21,
            ),
            _product(
                "Emamectin benzoate 5% SG", "insecticide", "88 g", "200 L",
                "Alternate group where larvae persist",
                phi_days=21,
            ),
            _product(
                "HaNPV 250 LE", "biological", "100 ml", "200 L",
                "Evening spray at low to moderate larval load",
                "Sunlight degrades it -- spray late in the day.",
            ),
        ],
        ["Put up bird perches: they take a real share of the larvae",
         "Pheromone traps tell you when the moth flight starts"],
        urgency="urgent",
    ),

    # -- maize ------------------------------------------------------------
    "maize_turcicum_blight": _treatment(
        "Long cigar-shaped lesions on the lower leaves. Worth spraying only "
        "once it reaches the leaves above the cob.",
        [
            _product(
                "Mancozeb 75% WP", "fungicide", "600 g", "200 L",
                "When lesions reach the leaf below the cob",
                phi_days=20,
            ),
            _product(
                "Azoxystrobin 23% SC", "fungicide", "200 ml", "200 L",
                "Where the season stays wet after the first spray",
                phi_days=30,
            ),
        ],
        ["Rotate out of maize and bury residue -- it survives on stubble"],
        urgency="soon",
    ),
    "maize_common_rust": _treatment(
        "Rarely worth a spray on grain maize unless it arrives early.",
        [
            _product(
                "Propiconazole 25% EC", "fungicide", "200 ml", "200 L",
                "Only if rust appears before tasselling",
                phi_days=30,
            ),
        ],
        ["Late-season rust on a filling cob usually costs less than the spray"],
        urgency="routine",
    ),
    "maize_fall_armyworm": _treatment(
        "The larva sits deep in the whorl. A spray that does not reach the "
        "whorl is a wasted tank -- direct it into the funnel.",
        [
            _product(
                "Emamectin benzoate 5% SG", "insecticide", "80 g", "200 L",
                "Into the whorl at 5-10% damaged plants",
                "Aim the spray into the whorl, not over the canopy.",
                phi_days=21,
            ),
            _product(
                "Spinetoram 11.7% SC", "insecticide", "200 ml", "200 L",
                "Alternate group; rotate every spray",
                phi_days=21,
            ),
            _product(
                "Bacillus thuringiensis var. kurstaki", "biological",
                "400 g", "200 L",
                "Early instars, evening application",
                "Works only on small larvae.",
            ),
        ],
        ["Sand plus lime in the whorl works on a small area and costs nothing",
         "Rotate insecticide groups every single spray -- resistance is fast here"],
        urgency="urgent",
    ),

    # -- mustard ----------------------------------------------------------
    "mustard_alternaria_blight": _treatment(
        "The commonest mustard disease in MP. Two protective sprays usually "
        "carry the crop through.",
        [
            _product(
                "Mancozeb 75% WP", "fungicide", "600 g", "200 L",
                "At the first dark concentric spots; repeat after 15 days",
                phi_days=20,
            ),
            _product(
                "Iprodione 25% + Carbendazim 25% WP", "fungicide", "400 g", "200 L",
                "Where the first spray did not hold",
                phi_days=30,
            ),
        ],
        ["Avoid late sowing -- it takes the worst of this",
         "Destroy infected stubble after harvest"],
        urgency="soon",
    ),
    "mustard_white_rust": _treatment(
        "Often arrives with Alternaria, and one protective spray covers both "
        "-- one tank, two problems.",
        [
            _product(
                "Metalaxyl 8% + Mancozeb 64% WP", "fungicide", "500 g", "200 L",
                "At the first white pustules on the underside of leaves",
                phi_days=25,
            ),
        ],
        ["Rogue staghead-deformed shoots and destroy them"],
        urgency="soon",
    ),
    "mustard_aphid": _treatment(
        "The single biggest yield loss in mustard. Spray in the evening, once "
        "pollinators have left the crop.",
        [
            _product(
                "Thiamethoxam 25% WG", "insecticide", "40 g", "200 L",
                "At 20-25 aphids per 10 cm of central twig",
                "Spray in the evening -- the crop is in flower and full of bees.",
                phi_days=21,
            ),
            _product(
                "Dimethoate 30% EC", "insecticide", "400 ml", "200 L",
                "Alternate group on a second flush",
                phi_days=21,
            ),
            _product(
                "Neem oil 1500 ppm", "biological", "500 ml", "200 L",
                "Low aphid load, or where flowering makes chemistry risky",
            ),
        ],
        ["Clip and destroy the first infested twigs -- the colony starts small",
         "Never spray a flowering mustard crop in the middle of the day"],
        urgency="urgent",
    ),

    # -- cotton -----------------------------------------------------------
    "cotton_leaf_curl": _treatment(
        "A virus. No spray treats it -- the target is the whitefly vector, and "
        "the plants already curled will not recover.",
        [
            _product(
                "Diafenthiuron 50% WP", "insecticide", "240 g", "200 L",
                "As soon as whitefly appears",
                phi_days=21,
            ),
            _product(
                "Flonicamid 50% WG", "insecticide", "60 g", "200 L",
                "Alternate group; rotate every spray",
                phi_days=21,
            ),
        ],
        ["Uproot and destroy severely curled plants",
         "Remove the alternate hosts on field margins",
         "Do not spray a fungicide for this -- it is a virus"],
        urgency="urgent",
    ),
    "cotton_bacterial_blight": _treatment(
        "Bacterial. Copper plus streptocycline, and stop the spread by not "
        "working a wet crop.",
        [
            _product(
                "Copper oxychloride 50% WP", "bactericide", "500 g", "200 L",
                "At the first angular water-soaked spots",
                phi_days=15,
            ),
            _product(
                "Streptocycline", "bactericide", "15 g", "200 L",
                "With the copper spray",
                "Restricted in some states -- check before planning the flight.",
                phi_days=15,
            ),
        ],
        ["Acid-delint and treat seed before next sowing",
         "Do not enter or spray a wet crop -- it spreads on contact"],
        urgency="urgent",
    ),
    "cotton_alternaria_spot": _treatment(
        "Late-season leaf spot. Worth treating only while there is still "
        "canopy left to protect.",
        [
            _product(
                "Mancozeb 75% WP", "fungicide", "600 g", "200 L",
                "At the first target-like spots; repeat after 15 days",
                phi_days=20,
            ),
        ],
        ["Correct potash -- deficient crops get much more of it"],
        urgency="routine",
    ),

    # -- pigeonpea --------------------------------------------------------
    "pigeonpea_wilt": _treatment(
        "Soil-borne. Nothing sprayed from the air reaches the root, and saying "
        "otherwise would sell a flight that cannot work.",
        [
            _product(
                "Trichoderma viride 1% WP", "biological",
                "5 g per kg seed / 2.5 kg per acre with FYM", "--",
                "Seed treatment at sowing, or soil application",
                "Not a drone spray.",
                drone_ready=False,
            ),
        ],
        ["Sow wilt-resistant varieties (Asha / ICPL series) on affected land",
         "Long rotation -- the fungus persists in soil for years",
         "Intercrop with sorghum, which suppresses it"],
        sprayable=False,
        urgency="routine",
    ),
    "pigeonpea_sterility_mosaic": _treatment(
        "A virus spread by eriophyid mite. The mite is the sprayable target.",
        [
            _product(
                "Fenazaquin 10% EC", "insecticide", "250 ml", "200 L",
                "At the first bushy, pale, flowerless shoots",
                phi_days=21,
            ),
            _product(
                "Wettable sulphur 80% WP", "insecticide", "1 kg", "200 L",
                "Alternate miticide spray",
                "Do not spray above about 32 C.",
                phi_days=15,
            ),
        ],
        ["Rogue affected plants -- they never set pod and stay a source",
         "Resistant varieties are the durable answer"],
        urgency="soon",
    ),

    # -- generic fallbacks ------------------------------------------------
    "healthy": _treatment(
        "Nothing to spray. The crop looks clean at this resolution.",
        [],
        ["Re-fly in 7-10 days -- change between two passes is the reliable signal"],
        sprayable=False,
        urgency="routine",
    ),
    "general_stress": _treatment(
        "The pattern is not diagnostic, so no product is recommended. Spraying "
        "against an unknown is how a season's chemical budget disappears "
        "without a yield change.",
        [],
        ["Ground-truth the patch before treating anything",
         "Check soil moisture and nutrition first -- they explain most of this",
         "Photograph the worst plants and ask the crop advisor for a second look"],
        sprayable=False,
        urgency="soon",
    ),
}


# -- Weeds -------------------------------------------------------------------
#
# Herbicide choice is driven far more by the *crop* than by the weed species: a
# product that clears broadleaf weeds out of wheat will flatten a soybean crop.
# So this is keyed by crop, and the weed type only narrows the choice within it.

HERBICIDES: Dict[str, List[Dict[str, Any]]] = {
    "wheat": [
        _product("Clodinafop-propargyl 15% WP", "herbicide", "160 g", "200 L",
                 "30-35 days after sowing, on actively growing grass weeds",
                 "Grass weeds (Phalaris, wild oat). Rotate the group every "
                 "season -- Phalaris resistance in MP is well established."),
        _product("Metsulfuron-methyl 20% WP", "herbicide", "8 g", "200 L",
                 "30-35 days after sowing",
                 "Broadleaf weeds only. Residue can damage a following pulse."),
        _product("Sulfosulfuron 75% WG", "herbicide", "13 g", "200 L",
                 "25-30 days after sowing",
                 "Covers grass and some broadleaf weeds in one pass."),
    ],
    "rice": [
        _product("Bispyribac-sodium 10% SC", "herbicide", "100 ml", "200 L",
                 "15-20 days after transplanting",
                 "Broad-spectrum post-emergence in transplanted paddy."),
        _product("Pretilachlor 50% EC", "herbicide", "600 ml", "200 L",
                 "3-5 days after transplanting, into standing water",
                 "Pre-emergence. Needs a thin water layer to work."),
        _product("2,4-D ethyl ester 38% EC", "herbicide", "500 ml", "200 L",
                 "20-25 days after transplanting",
                 "Sedges and broadleaf weeds. Drift damages nearby cotton and "
                 "vegetables badly -- check the wind before flying this."),
    ],
    "soybean": [
        _product("Imazethapyr 10% SL", "herbicide", "400 ml", "200 L",
                 "15-20 days after sowing, at the weed's 2-3 leaf stage",
                 "Grass and broadleaf. Residue restricts what can follow."),
        _product("Quizalofop-ethyl 5% EC", "herbicide", "400 ml", "200 L",
                 "15-20 days after sowing",
                 "Grass weeds only; safe over a broadleaf crop."),
        _product("Fomesafen 11.1% + Fluazifop-p-butyl 11.1% SL", "herbicide",
                 "400 ml", "200 L", "15-20 days after sowing",
                 "Both weed types in one pass."),
    ],
    "maize": [
        _product("Atrazine 50% WP", "herbicide", "400 g", "200 L",
                 "Pre-emergence, within 2 days of sowing",
                 "Do not use where a sensitive crop follows in the same season."),
        _product("Tembotrione 34.4% SC", "herbicide", "115 ml", "200 L",
                 "20-25 days after sowing",
                 "Post-emergence, grass and broadleaf."),
    ],
    "gram": [
        _product("Pendimethalin 30% EC", "herbicide", "1 L", "200 L",
                 "Pre-emergence, within 2-3 days of sowing"),
        _product("Imazethapyr 10% SL", "herbicide", "300 ml", "200 L",
                 "15-20 days after sowing"),
    ],
    "mustard": [
        _product("Pendimethalin 30% EC", "herbicide", "1 L", "200 L",
                 "Pre-emergence, within 2-3 days of sowing"),
        _product("Quizalofop-ethyl 5% EC", "herbicide", "400 ml", "200 L",
                 "15-20 days after sowing", "Grass weeds only."),
    ],
    "cotton": [
        _product("Pendimethalin 38.7% CS", "herbicide", "700 ml", "200 L",
                 "Pre-emergence"),
        _product("Pyrithiobac-sodium 10% EC", "herbicide", "250 ml", "200 L",
                 "20-25 days after sowing",
                 "Broadleaf weeds in standing cotton."),
    ],
    "pigeonpea": [
        _product("Pendimethalin 30% EC", "herbicide", "1 L", "200 L",
                 "Pre-emergence"),
        _product("Imazethapyr 10% SL", "herbicide", "300 ml", "200 L",
                 "15-20 days after sowing"),
    ],
}

# Used when the crop is unknown. Deliberately empty of chemistry: recommending
# a herbicide without knowing the crop is the one mistake in this file that
# would reliably destroy a field.
_UNKNOWN_CROP_HERBICIDE_NOTE = (
    "No herbicide can be recommended without knowing the crop -- the same "
    "product that clears a wheat field will kill a soybean one. Pick the crop "
    "and scan again."
)


def treatment_for(condition_id: Optional[str]) -> Dict[str, Any]:
    """The treatment entry for a detected condition. Never returns None."""
    key = str(condition_id or "").strip().lower()
    entry = TREATMENTS.get(key)
    if entry is not None:
        return {"condition_id": key, **entry}
    return {"condition_id": key or "general_stress", **TREATMENTS["general_stress"]}


def weed_treatment_for(
    crop_id: Optional[str], pressure_level: str = "moderate"
) -> Dict[str, Any]:
    """Herbicide options for a crop, plus whether it is worth flying at all."""
    key = str(crop_id or "").strip().lower()
    products = HERBICIDES.get(key, [])
    level = str(pressure_level or "none").lower()

    if level in ("none", "low"):
        return {
            "condition_id": "weeds",
            "summary": "Weed pressure is below the level where a herbicide "
                       "pays. Spot-weed instead of loading the tank.",
            "sprayable": False,
            "urgency": "routine",
            "products": [],
            "cultural": [
                "Hand-weed the scattered patches",
                "Re-scan in 7-10 days -- the window closes fast on a young crop",
            ],
            "disclaimer": DISCLAIMER,
        }

    if not products:
        return {
            "condition_id": "weeds",
            "summary": _UNKNOWN_CROP_HERBICIDE_NOTE,
            "sprayable": False,
            "urgency": "soon",
            "products": [],
            "cultural": ["Identify the crop, then re-scan for a herbicide option"],
            "disclaimer": DISCLAIMER,
        }

    return {
        "condition_id": "weeds",
        "summary": f"Weed pressure is {level}. The herbicide options registered "
                   f"for {key} are below -- choose by which weed type dominates.",
        "sprayable": True,
        "urgency": "urgent" if level == "high" else "soon",
        "products": products,
        "cultural": [
            "Treat inside the critical weed-free period; after it the yield is "
            "already lost and the spray only tidies the field",
            "Rotate herbicide groups between seasons -- resistance is the "
            "reason the old products stopped working",
        ],
        "disclaimer": DISCLAIMER,
    }


def spray_plan(
    conditions: List[Any],
    crop_id: Optional[str] = None,
    weed_pressure: Optional[str] = None,
) -> Dict[str, Any]:
    """One tank plan for everything a survey found.

    ``conditions`` are the aggregate's condition rows (``id``, ``name``,
    ``frame_share``, ``worst_severity``). The result groups the recommended
    products into passes that can share a tank, and names what cannot be
    sprayed at all -- a virus, a seed-borne disease, a soil-borne wilt -- so
    the operator does not fill for a flight that was never going to help.
    """
    passes: Dict[str, Dict[str, Any]] = {}
    not_sprayable: List[Dict[str, Any]] = []
    seen_products = set()

    def add(condition_name: str, treatment: Dict[str, Any]) -> None:
        if not treatment.get("sprayable"):
            not_sprayable.append({
                "condition": condition_name,
                "why": treatment.get("summary", ""),
                "instead": treatment.get("cultural", []),
            })
            return
        for product in treatment.get("products", []):
            if not product.get("drone_ready"):
                continue
            if product["name"] in seen_products:
                continue
            seen_products.add(product["name"])
            group = product.get("tank_group", "protectant")
            entry = passes.setdefault(group, {
                "tank_group": group,
                "tank_name": TANK_GROUP_NAMES.get(group, group.title()),
                "products": [],
                "targets": [],
            })
            entry["products"].append(product)
            if condition_name not in entry["targets"]:
                entry["targets"].append(condition_name)

    for condition in conditions or []:
        if isinstance(condition, dict):
            cid = condition.get("id")
            name = condition.get("name") or cid
        else:
            cid = str(condition)
            name = cid
        if cid == "healthy":
            continue
        add(name or "Unnamed condition", treatment_for(cid))

    if weed_pressure:
        add("Weeds", weed_treatment_for(crop_id, weed_pressure))

    ordered = sorted(passes.values(), key=lambda entry: entry["tank_group"])
    for index, entry in enumerate(ordered, 1):
        entry["pass"] = index
        # Only the first product of a group goes in the tank; the rest are the
        # alternates for the *next* spray. Listing five products as one load is
        # how a tank ends up full of unsprayable sludge.
        entry["load"] = entry["products"][0] if entry["products"] else None
        entry["alternates"] = entry["products"][1:]

    return {
        "passes": ordered,
        "pass_count": len(ordered),
        "needs_separate_passes": len(ordered) > 1,
        "not_sprayable": not_sprayable,
        "disclaimer": DISCLAIMER,
        "note": (
            "Each pass is one tank. Products listed as alternates are for the "
            "*following* spray, to rotate the chemical group -- not for the "
            "same load."
        ) if ordered else "Nothing here is worth loading a tank for.",
    }
