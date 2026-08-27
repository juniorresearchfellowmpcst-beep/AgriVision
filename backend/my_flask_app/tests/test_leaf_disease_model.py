"""Tests for the leaf-disease model seam.

The quiet failure modes here are the ones worth guarding:

  * a model label the app has never seen being turned into a confident
    diagnosis instead of being reported as unmapped;
  * the model's specific answer ("Tomato Late Blight") being collapsed into
    its treatment category ("Blight"), throwing away the crop and pathogen;
  * a photo with no leaf in it getting a disease name;
  * the model path silently losing the severity measurement, which comes from
    the pixels rather than the classifier.

The model itself is stubbed. These tests are about the wiring — whether a real
ResNet is accurate is what ``models/leaf_disease_report.json`` answers.
"""

import numpy as np
import pytest

from app.ai import disease_detector, leaf_labels, model_loader
from app.ai.disease_detector import DiseaseDetector


# ── label parsing ─────────────────────────────────────────────────────────

def test_fine_grained_label_splits_into_crop_and_condition():
    parsed = leaf_labels.parse("tomato___late_blight")
    assert parsed["crop_name"] == "Tomato"
    assert parsed["display_name"] == "Tomato Late Blight"
    assert parsed["knowledge_base_id"] == "blight"
    assert parsed["is_healthy"] is False


def test_healthy_label_reads_as_healthy():
    parsed = leaf_labels.parse("apple___healthy")
    assert parsed["is_healthy"] is True
    assert parsed["display_name"] == "Healthy Apple"
    assert parsed["knowledge_base_id"] == "healthy"


@pytest.mark.parametrize(
    "label, expected_condition",
    [
        # The specific class must win over the general one that is a substring
        # of it, or every blight collapses to the generic entry.
        ("potato___late_blight", "late_blight"),
        ("potato___early_blight", "early_blight"),
        ("corn___northern_leaf_blight", "northern_leaf_blight"),
        ("corn___gray_leaf_spot", "gray_leaf_spot"),
        ("tomato___septoria_leaf_spot", "septoria_leaf_spot"),
        ("apple___cedar_rust", "cedar_rust"),
        ("corn___common_rust", "common_rust"),
    ],
)
def test_specific_conditions_are_not_swallowed_by_general_ones(label, expected_condition):
    assert leaf_labels.parse(label)["condition"] == expected_condition


def test_other_naming_conventions_still_resolve():
    """A model trained on somebody else's folder names should still work."""
    assert leaf_labels.parse("Tomato___Late_blight")["condition"] == "late_blight"
    assert leaf_labels.parse("Tomato Late Blight")["condition"] == "late_blight"
    assert leaf_labels.parse("blight")["knowledge_base_id"] == "blight"


def test_unknown_label_is_reported_not_guessed():
    assert leaf_labels.parse("sorghum___ergot") is None

    described = leaf_labels.describe("sorghum___ergot")
    assert described["unmapped"] is True
    assert described["knowledge_base_id"] == "general_stress"
    assert described["display_name"] == "sorghum___ergot"


def test_background_class_is_not_a_leaf():
    assert leaf_labels.parse("not_a_leaf")["is_leaf"] is False


# ── detector wiring ───────────────────────────────────────────────────────

@pytest.fixture
def leaf_photo():
    """A green square with brown blotches — a leaf as far as the features go."""
    image = np.zeros((256, 256, 3), dtype=np.uint8)
    image[:, :] = (60, 170, 70)           # BGR green
    image[80:150, 80:150] = (40, 70, 110)  # brown necrosis
    ok, buffer = __import__("cv2").imencode(".jpg", image)
    assert ok
    return buffer.tobytes()


@pytest.fixture
def stub_model(monkeypatch):
    """Force the detector down the model path with a scripted ranking."""

    def install(ranking):
        monkeypatch.setattr(
            model_loader, "predict_topk", lambda img, k=3: ranking[:k]
        )
        monkeypatch.setattr(
            disease_detector.model_loader, "predict_topk", lambda img, k=3: ranking[:k]
        )

    return install


def test_model_answer_keeps_the_crop_and_names_its_advice_category(leaf_photo, stub_model):
    stub_model([("tomato___late_blight", 0.91), ("tomato___early_blight", 0.05)])
    result = DiseaseDetector.detect(leaf_photo)

    assert result["status"] == "ok"
    assert result["source"] == "model"
    # The specific finding is the headline...
    assert result["disease"]["name"] == "Tomato Late Blight"
    assert result["disease"]["crop"] == "Tomato"
    assert result["disease"]["label"] == "tomato___late_blight"
    # ...and the category says where the treatment text came from.
    assert result["disease"]["id"] == "blight"
    assert result["disease"]["category"]["id"] == "blight"
    assert result["solutions"], "treatment guidance must still be attached"


def test_runner_up_is_carried_back(leaf_photo, stub_model):
    stub_model([
        ("tomato___late_blight", 0.52),
        ("tomato___early_blight", 0.44),
        ("tomato___leaf_mold", 0.02),
    ])
    result = DiseaseDetector.detect(leaf_photo)

    names = [p["name"] for p in result["predictions"]]
    assert names[:2] == ["Tomato Late Blight", "Tomato Early Blight"]
    # A near-tie between two blights is not a settled answer.
    assert result["low_confidence"] is True
    assert "Tomato Early Blight" in result["message"]


def test_confident_model_answer_is_not_flagged_low_confidence(leaf_photo, stub_model):
    stub_model([("tomato___late_blight", 0.94)])
    result = DiseaseDetector.detect(leaf_photo)
    assert "low_confidence" not in result
    assert result["message"] == ""


def test_no_leaf_class_refuses_to_name_a_disease(leaf_photo, stub_model):
    stub_model([("not_a_leaf", 0.88)])
    result = DiseaseDetector.detect(leaf_photo)

    assert result["low_confidence"] is True
    assert "No leaf" in result["message"]
    assert result["is_healthy"] is False
    assert result["disease"]["id"] == "general_stress"


def test_severity_still_comes_from_the_pixels_on_the_model_path(leaf_photo, stub_model):
    """The classifier says which disease; the image says how much of the leaf."""
    stub_model([("tomato___late_blight", 0.9)])
    result = DiseaseDetector.detect(leaf_photo)

    assert result["severity"]["affected_percent"] > 0
    assert result["severity"]["level"] in ("low", "moderate", "high")
    assert result["observations"]["affected_fraction"] > 0


def test_healthy_model_answer_reports_no_severity(leaf_photo, stub_model):
    stub_model([("tomato___healthy", 0.97)])
    result = DiseaseDetector.detect(leaf_photo)

    assert result["is_healthy"] is True
    assert result["severity"] == {"level": "none", "affected_percent": 0}


def test_unmapped_model_label_is_flagged_rather_than_diagnosed(leaf_photo, stub_model):
    stub_model([("sorghum___ergot", 0.8)])
    result = DiseaseDetector.detect(leaf_photo)

    assert result["disease"]["unmapped"] is True
    assert result["disease"]["id"] == "general_stress"


def test_without_a_model_the_heuristic_still_answers(leaf_photo, monkeypatch):
    monkeypatch.setattr(model_loader, "predict_topk", lambda img, k=3: None)
    monkeypatch.setattr(
        disease_detector.model_loader, "predict_topk", lambda img, k=3: None
    )
    result = DiseaseDetector.detect(leaf_photo)

    assert result["status"] == "ok"
    assert result["source"] == "heuristic"
    assert result["disease"]["id"] in (
        "blight", "fungal_leaf_spot", "general_stress", "healthy",
        "nutrient_deficiency", "powdery_mildew", "pest_damage",
    )
    # No model means no per-crop claim.
    assert result["disease"]["crop"] is None


def test_unreadable_upload_is_an_error_not_a_diagnosis():
    result = DiseaseDetector.detect(b"this is not an image")
    assert result["status"] == "error"
    assert "disease" not in result


# ── dataset builder: cross-source label agreement ─────────────────────────

def _canonical_label():
    """Import the builder from tools/, which is not a package."""
    import os
    import sys

    tools = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tools")
    if tools not in sys.path:
        sys.path.insert(0, tools)
    from build_leaf_dataset import canonical_label

    return canonical_label


@pytest.mark.parametrize(
    "plantdoc_folder, plantvillage_folder",
    [
        # The same pathogen under each dataset's own name. If these ever stop
        # converging, the split correlates exactly with the background — grey
        # sheet versus real field — and the model will learn the background
        # instead of the disease, which is the whole reason PlantDoc is mixed in.
        ("Apple rust leaf", "Apple___Cedar_apple_rust"),
        ("Bell_pepper leaf spot", "Pepper,_bell___Bacterial_spot"),
        ("Corn leaf blight", "Corn___Northern_Leaf_Blight"),
        ("Corn Gray leaf spot", "Corn___Cercospora_leaf_spot Gray_leaf_spot"),
        ("Corn rust leaf", "Corn___Common_rust"),
        ("Tomato leaf late blight", "Tomato___Late_blight"),
        ("Tomato leaf bacterial spot", "Tomato___Bacterial_spot"),
        ("Tomato mold leaf", "Tomato___Leaf_Mold"),
        ("Tomato two spotted spider mites leaf", "Tomato___Spider_mites Two-spotted_spider_mite"),
        ("Tomato leaf yellow virus", "Tomato___Tomato_Yellow_Leaf_Curl_Virus"),
        ("grape leaf black rot", "Grape___Black_rot"),
        ("Apple Scab Leaf", "Apple___Apple_scab"),
        ("Soyabean leaf", "Soybean___healthy"),
        ("Squash Powdery mildew leaf", "Squash___Powdery_mildew"),
    ],
)
def test_both_datasets_agree_on_a_shared_class(plantdoc_folder, plantvillage_folder):
    canonical_label = _canonical_label()
    assert canonical_label(plantdoc_folder) == canonical_label(plantvillage_folder)


def test_every_built_class_is_understood_by_the_backend():
    """The builder's output must be readable by app/ai/leaf_labels.py.

    These are two separate modules with two separate tables, and a class the
    trainer emits but the server cannot name would reach the farmer as an
    unmapped raw string.
    """
    canonical_label = _canonical_label()
    folders = [
        "Apple___Apple_scab", "Apple___Black_rot", "Apple___Cedar_apple_rust",
        "Cherry___Powdery_mildew", "Corn___Cercospora_leaf_spot Gray_leaf_spot",
        "Corn___Common_rust", "Corn___Northern_Leaf_Blight", "Grape___Black_rot",
        "Grape___Esca_(Black_Measles)", "Grape___Leaf_blight_(Isariopsis_Leaf_Spot)",
        "Orange___Haunglongbing_(Citrus_greening)", "Peach___Bacterial_spot",
        "Pepper,_bell___Bacterial_spot", "Potato___Early_blight",
        "Potato___Late_blight", "Squash___Powdery_mildew",
        "Strawberry___Leaf_scorch", "Tomato___Bacterial_spot",
        "Tomato___Early_blight", "Tomato___Late_blight", "Tomato___Leaf_Mold",
        "Tomato___Septoria_leaf_spot", "Tomato___Target_Spot",
        "Tomato___Tomato_Yellow_Leaf_Curl_Virus", "Tomato___Tomato_mosaic_virus",
        "Tomato___Spider_mites Two-spotted_spider_mite", "Tomato___healthy",
        "Background_without_leaves",
    ]
    for folder in folders:
        label = canonical_label(folder)
        assert label is not None, f"builder could not place {folder!r}"
        assert leaf_labels.parse(label) is not None, (
            f"builder emits {label!r} but leaf_labels cannot read it"
        )
