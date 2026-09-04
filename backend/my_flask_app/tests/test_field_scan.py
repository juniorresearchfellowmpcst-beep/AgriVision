"""Tests for the weed detector and the crop-disease field scan.

The two failure modes that matter here are quiet ones:

  * calling the crop "weeds" (or vice versa), which would send a herbicide
    recommendation for the thing being grown;
  * turning a dataset label the app has never heard of into a confident
    diagnosis.

Synthetic canopies throughout — a field whose rows and weeds we drew ourselves
is the only way to know what the right answer was.
"""

import glob
import cv2
import numpy as np
import pytest

from app.ai import field_scan
from app.ai.canopy import extract_canopy_features
from app.ai.crop_kb import diseases_for, get_disease
from app.ai.crop_model import map_disease_label, map_weed_label
from app.ai.weed_detector import detect, find_rows, vegetation_mask
from app.ai.weed_kb import pressure_for

SIZE = 512
SOIL = (60, 80, 125)      # BGR: reddish-brown MP soil
CROP_GREEN = (40, 160, 50)
WEED_GREEN = (70, 195, 80)
RUST_YELLOW = (40, 220, 230)


def _row_crop(weed_blobs=6):
    """A row crop on bare soil, with weed blobs sitting between the rows."""
    image = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    image[:, :] = SOIL

    spacing, width = 50, 20
    for x in range(10, SIZE, spacing):
        image[:, x:x + width] = CROP_GREEN

    # Weeds go in the middle of the gaps, where no crop is sown.
    rng = np.random.default_rng(3)
    for _ in range(weed_blobs):
        row_index = int(rng.integers(0, SIZE // spacing - 1))
        cx = 10 + row_index * spacing + width + (spacing - width) // 2
        cy = int(rng.integers(40, SIZE - 40))
        cv2.circle(image, (cx, cy), 12, WEED_GREEN, -1)
    return image


def _clean_row_crop():
    return _row_crop(weed_blobs=0)


def _uniform_canopy(colour=CROP_GREEN):
    image = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    image[:, :] = colour
    return image


def _rusted_canopy():
    """A green canopy carrying long thin yellow stripes — the yellow-rust look."""
    image = _uniform_canopy()
    for i in range(8):
        x = 40 + i * 55
        cv2.rectangle(image, (x, 60), (x + 6, 420), RUST_YELLOW, -1)
    return image


# ── vegetation + rows ────────────────────────────────────────────────────

def test_vegetation_mask_separates_canopy_from_soil():
    mask, coverage = vegetation_mask(_row_crop())
    assert 0.2 < coverage < 0.7, "rows cover part of the frame, not all of it"
    # Soil corners must be excluded.
    assert mask[0, 0] == 0


def test_bare_soil_has_no_vegetation():
    soil = np.zeros((256, 256, 3), dtype=np.uint8)
    soil[:, :] = SOIL
    _mask, coverage = vegetation_mask(soil)
    assert coverage < 0.02


def test_row_structure_is_found_in_a_row_crop():
    mask, _coverage = vegetation_mask(_row_crop())
    rows = find_rows(mask)
    assert rows["found"] is True
    assert rows["row_spacing_px"] > 0


def test_no_row_structure_in_a_uniform_canopy():
    mask, _coverage = vegetation_mask(_uniform_canopy())
    rows = find_rows(mask)
    assert rows["found"] is False


# ── weed detection ───────────────────────────────────────────────────────

def test_inter_row_weeds_are_detected():
    result = detect(_row_crop(weed_blobs=8), crop="soybean")
    assert result["method"] == "inter-row"
    assert result["weed_coverage"] > 0.005
    assert result["patches"], "weed blobs should survive as patches"
    assert result["confidence"] >= 0.5


def test_a_clean_row_crop_reports_little_or_no_weed():
    weedy = detect(_row_crop(weed_blobs=10), crop="soybean")
    clean = detect(_clean_row_crop(), crop="soybean")
    # The crop itself must not be counted as weed: a clean field has to score
    # well below a weedy one.
    assert clean["weed_coverage"] < weedy["weed_coverage"]


def test_weed_result_names_the_crop_s_usual_suspects():
    result = detect(_row_crop(), crop="wheat")
    names = [weed["id"] for weed in result["likely_weeds"]]
    assert "phalaris_minor" in names

    result = detect(_row_crop(), crop="rice")
    names = [weed["id"] for weed in result["likely_weeds"]]
    assert "echinochloa" in names


def test_bare_frame_is_reported_rather_than_guessed():
    soil = np.zeros((256, 256, 3), dtype=np.uint8)
    soil[:, :] = SOIL
    result = detect(soil)
    assert result["weed_coverage"] == 0.0
    assert result["method"] == "none"
    assert "vegetation" in result["note"]


def test_pressure_bands_are_ordered():
    assert pressure_for(0.0)["level"] == "none"
    assert pressure_for(0.05)["level"] == "low"
    assert pressure_for(0.15)["level"] == "moderate"
    assert pressure_for(0.5)["level"] == "high"


# ── canopy features + disease ────────────────────────────────────────────

def test_canopy_features_ignore_the_soil_between_rows():
    """The leaf extractor would call reddish soil 'necrotic tissue'; the canopy
    extractor must not, or every healthy field reads as diseased."""
    features = extract_canopy_features(_row_crop(weed_blobs=0))
    assert features["canopy_found"] is True
    assert features["green_fraction"] > 0.75
    assert features["brown_fraction"] < 0.2


def test_healthy_canopy_scans_clean():
    result = field_scan.scan_frame(_uniform_canopy(), crop="wheat")
    assert result["status"] == "ok"
    assert result["is_healthy"] is True
    assert result["severity"]["level"] == "none"


def _glossy_canopy():
    """A healthy canopy with sunlight glinting off the leaves.

    Waxy foliage in direct sun throws back near-white specular highlights.
    They are the light source, not the leaf, and they are what made a clean
    maize plant come back as "Turcicum leaf blight".
    """
    image = _uniform_canopy()
    for i in range(9):
        x = 20 + i * 55
        # Bright and almost colourless — a reflection, not a coating.
        cv2.rectangle(image, (x, 30), (x + 14, 450), (246, 248, 246), -1)
    return image


def test_leaf_glare_is_not_read_as_a_fungal_coating():
    """The operator's bug: a clean sunlit plant diagnosed with a blight.

    A highlight is bright and unsaturated, which is also what a white fungal
    coating looks like to a colour test. Counting it as symptom turned glossy
    maize foliage into 80% "white" and produced a named disease, a Mancozeb
    dose and a pre-harvest interval over a crop with nothing wrong with it.
    """
    features = extract_canopy_features(_glossy_canopy())

    assert features["highlight_fraction"] > 0.05, "the glare should be seen"
    # ...and then discounted, rather than counted as a symptom.
    assert features["white_fraction"] < 0.15
    assert features["green_fraction"] > 0.80


def test_colour_shares_do_not_double_count_the_leaf():
    """The bands partition the readable leaf; they used to overlap.

    `healthy` and `white` both claimed saturation 45-55, so the shares could
    sum past 1 and a pixel could be evidence for two conclusions at once.
    """
    for image in (_uniform_canopy(), _glossy_canopy(), _rusted_canopy()):
        features = extract_canopy_features(image)
        total = sum(
            features[f"{name}_fraction"]
            for name in ("green", "yellow", "orange", "brown", "white", "grey")
        )
        assert total <= 1.001, f"shares sum to {total}"


def test_a_signature_matching_nothing_is_not_given_a_disease_name():
    """Abstaining beats naming the least-bad entry in the list.

    `scored` is never empty, so without a floor the classifier always returns
    *something* — and the knowledge base then attaches a product and a
    pre-harvest interval to it. Measured over the corn sets, healthy frames sit
    at the 0.16 "matched nothing" floor while real infections reach 0.46 at the
    lower quartile, so this refuses the first without hiding the second.
    """
    # Grey-blue is not a colour any maize disease presents as.
    odd = field_scan.classify_heuristic(
        extract_canopy_features(_uniform_canopy(colour=(150, 150, 120))),
        "maize",
    )
    assert odd["condition_id"] != "maize_turcicum_blight"

    # And whatever it does say must carry no spray recommendation.
    if odd["condition_id"] == "general_stress":
        from app.ai import treatment_kb

        assert treatment_kb.treatment_for("general_stress")["sprayable"] is False


def test_a_real_symptom_still_gets_named():
    """The floor must not be a mute button: yellow streaks are still rust."""
    result = field_scan.classify_heuristic(
        extract_canopy_features(_rusted_canopy()), "wheat"
    )
    assert result["condition_id"] not in ("healthy", "general_stress")
    assert result["confidence"] >= 0.4


def test_yellow_streaks_on_wheat_read_as_a_wheat_disease():
    result = field_scan.scan_frame(_rusted_canopy(), crop="wheat")
    assert result["status"] == "ok"
    assert not result["is_healthy"]

    wheat_ids = {disease["id"] for disease in diseases_for("wheat")}
    assert result["disease"]["id"] in wheat_ids
    # Colour + pattern narrow it; they do not confirm a pathogen, so the
    # heuristic must stay modest.
    assert result["disease"]["confidence"] <= 0.7
    assert result["disease"]["source"] == "heuristic"
    assert result["disclaimer"]


def test_the_same_symptom_maps_differently_per_crop():
    """Yellowing means different things in wheat and soybean — the crop is
    part of the diagnosis, not decoration."""
    wheat = field_scan.scan_frame(_rusted_canopy(), crop="wheat")["disease"]["id"]
    soybean = field_scan.scan_frame(_rusted_canopy(), crop="soybean")["disease"]["id"]
    assert wheat != soybean


def test_unknown_crop_says_so_instead_of_naming_a_disease():
    result = field_scan.scan_frame(_rusted_canopy(), crop=None)
    assert result["disease"]["id"] in ("general_stress", "healthy")


def test_scan_produces_actions():
    result = field_scan.scan_frame(_row_crop(weed_blobs=12), crop="soybean")
    assert result["actions"]
    assert result["actions"][0]["order"] == 1


# ── aggregation ──────────────────────────────────────────────────────────

def test_aggregate_summarises_a_pass():
    frames = [
        field_scan.scan_frame(_rusted_canopy(), crop="wheat"),
        field_scan.scan_frame(_uniform_canopy(), crop="wheat"),
        field_scan.scan_frame(_rusted_canopy(), crop="wheat"),
    ]
    for index, frame in enumerate(frames):
        frame["frame_id"] = index
        frame["lat"], frame["lon"] = 23.2 + index * 0.0001, 77.4

    summary = field_scan.aggregate(frames, crop="wheat")
    assert summary["status"] == "ok"
    assert summary["frames"] == 3
    assert summary["diseased_frames"] == 2
    assert summary["disease_incidence"] == pytest.approx(2 / 3, abs=0.01)
    assert summary["dominant_problem"]["frames"] == 2
    assert summary["actions"]
    assert "frame(s) scanned" in summary["summary"]


def test_aggregate_with_nothing_scannable():
    assert field_scan.aggregate([])["status"] == "error"


# ── label mapping ────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "label, crop, expected",
    [
        ("Wheat___Yellow_Rust", None, "wheat_yellow_rust"),
        ("wheat_leaf_rust", "wheat", "wheat_brown_rust"),
        ("BrownSpot", "rice", "rice_brown_spot"),
        ("Leaf blast", "rice", "rice_blast"),
        ("rust", "soybean", "soybean_rust"),
        ("healthy", "wheat", "healthy"),
    ],
)
def test_dataset_labels_map_onto_knowledge_base_ids(label, crop, expected):
    mapping = map_disease_label(label, crop)
    assert mapping["id"] == expected
    assert mapping["matched"] is True


def test_the_same_bare_label_resolves_per_crop():
    """'rust' is a different disease in wheat and in soybean; the mapper must
    scope to the crop rather than pick whichever it saw first."""
    assert map_disease_label("rust", "soybean")["id"] == "soybean_rust"
    assert map_disease_label("rust", "maize")["id"] == "maize_common_rust"


def test_unmappable_label_is_reported_not_forced():
    mapping = map_disease_label("Tomato___Septoria_leaf_spot_xyz", "wheat")
    assert mapping["matched"] is False
    assert get_disease(mapping["id"])["id"] == "general_stress"


@pytest.mark.parametrize(
    "label, expected",
    [
        # The whole reason the shipped model was unusable on the crop path.
        ("corn___healthy", "healthy"),
        ("corn___common_rust", "maize_common_rust"),
        # Northern corn leaf blight and Turcicum leaf blight are one disease.
        ("corn___northern_leaf_blight", "maize_turcicum_blight"),
        ("Corn Northern Leaf Blight", "maize_turcicum_blight"),
        ("corn___gray_leaf_spot", "maize_gray_leaf_spot"),
    ],
)
def test_the_shipped_models_corn_classes_all_map_to_maize(label, expected):
    """PlantVillage says "corn"; this app says "maize".

    Nothing connected the two, so the crop prefix was never stripped and stayed
    in the token set poisoning every match after it -- "corn___healthy" no
    longer equalled "healthy", and a photograph of a *healthy maize leaf* came
    back as general stress. All four of the model's corn classes have to land,
    or wiring the model in makes the app worse rather than better.
    """
    mapping = map_disease_label(label, "maize")
    assert mapping["matched"] is True
    assert mapping["id"] == expected


def test_a_label_from_a_crop_this_app_does_not_grow_is_refused():
    """A tomato disease must never resolve to a cotton one.

    The public datasets carry a dozen crops this app has no entries for. Left
    to the widening step these matched on a shared token -- bacterial spot
    resolved to cotton's bacterial blight -- and would have carried cotton's
    product and dose with them.
    """
    for label in (
        "tomato___bacterial_spot",
        "tomato___yellow_leaf_curl_virus",
        "potato___late_blight",
        "pepper___healthy",
    ):
        assert map_disease_label(label, None)["matched"] is False


def test_a_label_naming_a_different_crop_than_the_scan_is_refused():
    """The model disagreeing about the crop is information, not a diagnosis.

    A wheat scan fed a corn leaf had "corn___common_rust" widened onto maize's
    common rust and reported under wheat.
    """
    mapping = map_disease_label("corn___common_rust", "wheat")
    assert mapping["matched"] is False
    assert mapping["id"] == "general_stress"

    # ...and the same label under its own crop still resolves.
    assert map_disease_label("corn___common_rust", "maize")["matched"] is True


def test_an_unmapped_model_answer_falls_back_to_the_rules():
    """Switching the model on must not downgrade the crops it never learnt.

    It covers maize and almost nothing else Madhya Pradesh grows, so a wheat
    or gram scan reaches the unmapped branch every time. Returning the model's
    shrug there would trade a rough named answer for no answer at all.
    """
    result = field_scan.scan_frame(_rusted_canopy(), crop="wheat")

    assert result["status"] == "ok"
    assert result["disease"]["source"] == "heuristic"
    assert result["disease"]["name"] != "General stress"


def test_weed_labels_map_to_weed_ids():
    assert map_weed_label("Phalaris minor")["id"] == "phalaris_minor"
    assert map_weed_label("purple nutsedge")["id"] == "cyperus_rotundus"
    assert map_weed_label("some_unknown_plant")["matched"] is False


def test_the_aerial_path_does_not_use_the_leaf_model():
    """A leaf classifier must not judge a frame taken from altitude.

    It does not recognise an aerial view as out of domain -- shown a canopy it
    answers confidently and never reaches for its own `not_a_leaf` class.
    Confident and out-of-domain is the dangerous pair here, because the failure
    it produces is a diseased block reported as healthy, and there is no
    labelled aerial set to measure that on. So the aerial path keeps the
    detector whose behaviour on aerial frames is known.
    """
    aerial = field_scan.scan_frame(_row_crop(weed_blobs=0), crop="maize",
                                   framing="canopy")
    assert aerial["disease"]["source"] == "heuristic"


def test_a_phone_closeup_does_use_the_model():
    """The path the measurement was taken on, and the default."""
    from app.ai import crop_model

    if not crop_model.disease_model.is_available():
        pytest.skip("no crop-disease model on this machine")

    leaf = cv2.imread(
        sorted(glob.glob("datasets/leaf_disease/corn___common_rust/*.jpg"))[0]
    )
    if leaf is None:
        pytest.skip("leaf dataset not present on this machine")

    result = field_scan.scan_frame(leaf, crop="maize")
    assert result["disease"]["source"] == "model"
