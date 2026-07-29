# AgriVision — Image Detection Modules

Technical documentation for the two image-based analysis features in AgriVision,
and a reference for every vegetation index the field analyser uses.

| # | Module | Input | What it produces | Technique |
|---|--------|-------|------------------|-----------|
| A | **Plant Disease Identification** | One RGB photo of a leaf (camera or gallery) | Likely condition + severity + treatment/solution | Rule-based computer-vision heuristic (OpenCV), with an optional pluggable deep-learning model |
| B | **Multispectral Field Image Analysis** | Multi-band aerial/field images (blue, green, red, red-edge, NIR) | Vegetation indices + health score + high/medium/low risk zones + action plan | Reflectance-based index computation + K-means zoning |

> **Read this first — about "the model", "dataset" and "accuracy".**
> Neither module currently uses a *trained* machine-learning model or a labelled
> training dataset. Both are **deterministic, explainable algorithms**:
> Module A classifies a leaf from measured colour/lesion features against fixed
> rules; Module B computes physically-defined reflectance indices and clusters
> them. Because nothing was *trained* on a labelled dataset, **no test-set
> accuracy figure is claimed** — doing so would be misleading. Module A ships a
> clean, documented seam to drop in a real CNN later (see
> [§A.7](#a7-optional-trained-model-interface)), and that is where a dataset and
> a measured accuracy would enter. This document states exactly what *is*
> implemented and what the tunable **parameters** are.

---

## Table of contents

- [Module A — Plant Disease Identification](#module-a--plant-disease-identification)
  - [A.1 Data flow](#a1-data-flow)
  - [A.2 Code map](#a2-code-map)
  - [A.3 What model / dataset does it use?](#a3-what-model--dataset-does-it-use)
  - [A.4 Feature extraction parameters](#a4-feature-extraction-parameters)
  - [A.5 Classification rules](#a5-classification-rules)
  - [A.6 Severity, confidence & knowledge base](#a6-severity-confidence--knowledge-base)
  - [A.7 Optional trained-model interface](#a7-optional-trained-model-interface)
  - [A.8 API reference](#a8-api-reference)
  - [A.9 Limitations](#a9-limitations)
- [Module B — Multispectral Field Image Analysis](#module-b--multispectral-field-image-analysis)
  - [B.1 Pipeline](#b1-pipeline)
  - [B.2 Parameters](#b2-parameters)
  - [B.3 API reference](#b3-api-reference)
- [Vegetation Indices — introduction & significance](#vegetation-indices--introduction--significance)
  - [What a vegetation index is](#what-a-vegetation-index-is)
  - [Bands used](#bands-used)
  - [Full index reference (21 indices)](#full-index-reference-21-indices)
  - [Significance of each index](#significance-of-each-index)
- [Running & testing](#running--testing)

---

# Module A — Plant Disease Identification

Lets a user **take or upload a photo of a single plant leaf** and returns the
most likely problem together with a farmer-readable **solution** (symptoms,
causes, treatment options grouped by type, and prevention).

## A.1 Data flow

```
Flutter app                          Flask backend
───────────                          ─────────────
Take photo / pick from gallery
  (image_picker, resized to ≤1600px)
        │  multipart POST
        ▼
  /api/disease/identify  ──────────► disease_routes.py
                                        │
                                        ▼
                                     DiseaseService.identify()
                                        │
                                        ▼
                                     DiseaseDetector.detect()
                                        │  decode (OpenCV)
                                        ├─► utils.extract_features()   (colour + lesion features)
                                        ├─► model_loader.predict()     (only if a model is configured)
                                        └─► knowledge_base.get_condition()  (symptoms + solutions)
        ◄──────────────────────────── JSON: disease, severity, solutions, ...
  DiseaseResult → DiseaseCubit → DiseasePage renders cards
```

## A.2 Code map

**Backend** (`backend/my_flask_app/`)

| File | Responsibility |
|------|----------------|
| `app/ai/utils.py` | Decode image, segment the leaf, extract colour/lesion features |
| `app/ai/disease_detector.py` | Classify features → condition; assemble the response |
| `app/ai/knowledge_base.py` | Symptoms / causes / **solutions** / prevention per condition |
| `app/ai/model_loader.py` | Optional TorchScript model hook (lazy, cached, fail-safe) |
| `app/services/disease_service.py` | Validation + orchestration; returns `(dict, status)` |
| `app/api/routes/disease_routes.py` | `GET /health`, `POST /identify`; blueprint `/api/disease` |

**Frontend** (`Frontend/agri_vision/`)

| File | Responsibility |
|------|----------------|
| `lib/src/core/utils/plant_photo_picker.dart` | Camera + gallery capture via `image_picker` |
| `lib/src/data/disease/disease_service.dart` | Multipart upload to the endpoint (Dio) |
| `lib/src/domain/entity/disease_result.dart` | Typed model of the response |
| `lib/src/ui/cubit/disease/disease_cubit.dart` | State machine (idle → analysing → success/failure) |
| `lib/src/ui/view/Disease/disease_page.dart` | Result UI (diagnosis, severity, solution cards) |

## A.3 What model / dataset does it use?

**By default: none — it is a rule-based computer-vision heuristic.**

- **No neural network is trained or run** in the default configuration.
- **No labelled training dataset** (e.g. PlantVillage) is used, because nothing
  is trained. The "knowledge" is the curated agronomic content in
  `knowledge_base.py`, authored by hand.
- The classifier is **deterministic and explainable**: the same photo always
  yields the same result, and every decision can be traced to the pixel
  measurements in [§A.4](#a4-feature-extraction-parameters) and the thresholds
  in [§A.5](#a5-classification-rules).
- Runs **fully offline** using only OpenCV + NumPy (already in `requirements.txt`).

Why this design: a single RGB phone photo reliably reveals a *visual category*
of stress (healthy vs yellowing vs spotting vs large necrosis vs white coating),
but naming an exact pathogen/strain from one uncalibrated photo is not
dependable. The module therefore reports a **category with a confidence score**
and always shows a disclaimer that it is an automated **screening, not a lab
diagnosis**. When higher precision is required, plug in a trained model
([§A.7](#a7-optional-trained-model-interface)) — that is the correct place for a
dataset and a measured accuracy.

## A.4 Feature extraction parameters

`utils.extract_features()` works in HSV (OpenCV ranges: H 0–179, S/V 0–255).
All `*_fraction` values are shares of the detected **leaf** area, so they are
independent of how much background is in frame.

| Stage | Parameter | Value |
|-------|-----------|-------|
| Pre-resize | Longest edge (`_MAX_EDGE`) | 720 px |
| Leaf mask — vegetation | Coloured tissue | `S > 40 and V > 30 and H ≤ 95` |
| Leaf mask — dark tissue | Necrotic/shadowed | `V < 90 and S > 20` |
| Leaf mask — silhouette | Close kernel / fill / erode | 15×15 ellipse, ×2, fill holes, erode ×1 |
| Leaf mask — white coating | Bright desaturated inside leaf | `S < 45 and V ≥ 170` (kept only inside the leaf silhouette) |
| "Leaf found?" gate | Minimum leaf area | `≥ max(500 px, 2% of frame)` |
| Colour class — healthy green | | `H 35–90, S ≥ 45, V ≥ 40` |
| Colour class — yellow (chlorotic) | | `H 20–35, S ≥ 45, V ≥ 60` |
| Colour class — white (mildew) | | `S < 45, V ≥ 170` |
| Colour class — brown/necrotic | | `(H ≤ 20 or H ≥ 160) or V < 110`, minus green/white/yellow |
| Lesion blobs | Min blob area (noise floor) | `max(12 px, 0.08% of leaf)`, 8-connectivity |

Derived features returned: `green/yellow/brown/white_fraction`,
`affected_fraction = 1 − green_fraction`, `spot_count` (discrete lesions),
`largest_lesion_fraction`, and `leaf_coverage`.

> **Design note (do not "simplify" away):** the leaf mask deliberately folds
> bright, low-saturation pixels that fall *inside* the leaf silhouette back into
> the leaf. Without this, a white powdery-mildew coating is discarded as
> "background" and powdery mildew can never be detected.

## A.5 Classification rules

`DiseaseDetector._classify()` evaluates these rules in order and returns the
first match, with a confidence score. `green/yellow/brown/white` below are the
leaf-area fractions; `spots` is `spot_count`; `largest` is
`largest_lesion_fraction`.

| Order | Condition | Rule | Confidence |
|-------|-----------|------|------------|
| 1 | **Healthy** | `affected < 0.12 and white < 0.05 and spots < 5` | `0.75 + 0.2·green`, ≤ 0.95 |
| 2 | **Powdery mildew** | `white ≥ 0.06 and white ≥ brown` | `0.55 + white`, ≤ 0.90 |
| 3 | **Blight** | `largest ≥ 0.20 and brown ≥ 0.08 and brown ≥ yellow` | `0.5 + largest`, ≤ 0.90 |
| 4 | **Fungal/bacterial leaf spot** | `spots ≥ 5 and brown ≥ yellow` | `0.5 + (spots/40 + brown)`, ≤ 0.90 |
| 5 | **Leaf spot (broad browning)** | `brown ≥ 0.10 and brown ≥ yellow` | `0.45 + brown`, ≤ 0.85 |
| 6 | **Nutrient deficiency / chlorosis** | `yellow ≥ 0.12 and yellow ≥ brown` | `0.5 + yellow`, ≤ 0.85 |
| 7 | **General stress (inconclusive)** | fallback | `0.35 + 0.3·affected` |

A separate guard returns **General stress (low confidence)** with a "couldn't
detect a leaf" hint when the leaf gate in §A.4 fails.

## A.6 Severity, confidence & knowledge base

**Severity** (from `affected_fraction`, i.e. non-green leaf area):

| Level | Rule |
|-------|------|
| none | condition is *healthy* |
| low | `affected < 0.20` |
| moderate | `0.20 ≤ affected < 0.50` |
| high | `affected ≥ 0.50` |

`affected_percent = round(affected_fraction × 100)` is shown to the user.

**Knowledge base** — 7 conditions, each with a description, symptoms, causes,
grouped **solutions** (`cultural` / `organic` / `chemical` / `monitoring`) and
prevention tips:

| id | Name | Visual trigger |
|----|------|----------------|
| `healthy` | Healthy plant | Uniform green, no lesions |
| `nutrient_deficiency` | Nutrient deficiency / chlorosis | Widespread yellowing |
| `fungal_leaf_spot` | Fungal / bacterial leaf spot | Many discrete spots |
| `blight` | Blight (early/late type) | Large necrotic blotches |
| `powdery_mildew` | Powdery mildew | White/grey coating |
| `pest_damage` | Pest / physical damage | Holes, ragged edges |
| `general_stress` | General leaf stress (inconclusive) | Unclear pattern |

## A.7 Optional trained-model interface

To upgrade from the heuristic to a real classifier **without changing any
route/service code**, drop in a [TorchScript](https://pytorch.org/docs/stable/jit.html)
model and set two environment variables:

```bash
AI_DISEASE_MODEL_PATH=/abs/path/model.pt      # torch.jit ScriptModule
AI_DISEASE_LABELS_PATH=/abs/path/labels.txt   # one class name per line
```

Contract enforced by `model_loader.py`:

| Item | Value |
|------|-------|
| Input | RGB, resized to **224 × 224** |
| Normalisation | mean `[0.485, 0.456, 0.406]`, std `[0.229, 0.224, 0.225]` (ImageNet) |
| Output | logits → `softmax`; top-1 label + confidence |
| Label mapping | label text is normalised onto the knowledge-base ids (e.g. `early_blight` → `blight`); unknown labels fall back to `general_stress` |
| Failure handling | any load/inference error is logged and the module **falls back to the heuristic** — the endpoint never fails because a model is misconfigured |

**This is where a dataset and accuracy belong.** A typical path: train a CNN
(e.g. ResNet/MobileNet) on a labelled leaf-disease dataset such as
[PlantVillage](https://arxiv.org/abs/1511.08060), export with `torch.jit.script`
/ `torch.jit.trace`, write the class names to `labels.txt`, and report the model's
**top-1 accuracy / macro-F1 on a held-out test split** and a confusion matrix.
Until such a model is supplied, AgriVision makes **no accuracy claim**.

## A.8 API reference

**`GET /api/disease/health`** → capabilities and active engine.
```json
{ "status":"ok", "feature":"plant-disease-identification",
  "engine":"heuristic", "conditions":["healthy","nutrient_deficiency", ...] }
```

**`POST /api/disease/identify`** — `multipart/form-data`, one image part (any
field name). Max 12 MB. Response (trimmed):
```json
{
  "status": "ok",
  "is_healthy": false,
  "confidence": 0.85,
  "source": "heuristic",
  "disease": { "id":"fungal_leaf_spot", "name":"Fungal / bacterial leaf spot",
               "also_known_as":"Leaf spot", "description":"..." },
  "severity": { "level":"low", "affected_percent":10 },
  "symptoms": ["..."], "causes": ["..."],
  "solutions": [ { "type":"cultural", "title":"Remove infected leaves", "detail":"..." } ],
  "prevention": ["..."],
  "observations": { "green_fraction":0.91, "brown_fraction":0.08, "spot_count":22, ... },
  "disclaimer": "This is an automated visual screening ..."
}
```

## A.9 Limitations

- Reports a **visual category**, not a specific pathogen or strain.
- Best on **one well-lit leaf on a plain background**; busy backgrounds, multiple
  leaves, or heavy shadow reduce reliability.
- Colour thresholds assume roughly natural white-balance; extreme lighting can
  shift results.
- Pest/physical damage (holes) is in the knowledge base but hard to detect from
  colour alone — treat that class as advisory.
- **Not a substitute for expert diagnosis** before applying chemical treatment.

---

# Module B — Multispectral Field Image Analysis

Turns a set of multispectral band images into a field-health report. Also **not**
a trained model — it computes physically-defined reflectance indices and clusters
them into risk zones.

## B.1 Pipeline

`app/preprocessing/` : `reflectance → alignment → indices → risk/report → action plan`

1. **Reflectance** — with a calibration-panel photo, bands are converted to true
   reflectance; without one, each capture is rescaled to **pseudo-reflectance**
   using a **single shared scale across all bands** (global 99.9th percentile).
   Results are then *relative* (good for zoning) rather than absolute.
2. **Band alignment** — co-registers the bands.
3. **Indices** — computes the vegetation indices the available bands support
   (see the [full reference](#full-index-reference-21-indices)).
4. **Risk zoning** — K-means clusters a chosen health index into HIGH / MEDIUM /
   LOW risk regions and renders a stoplight map.
5. **Report + action plan** — health score, flagged issues, and a prioritised,
   index-driven checklist.

## B.2 Parameters

| Parameter | Value / rule |
|-----------|--------------|
| Pseudo-reflectance scale | Global **99.9th percentile**, shared across bands |
| Risk clustering | **K-means, k = 3** on the primary index |
| Risk mapping | For a *higher-is-healthier* index, the **lowest** cluster = **high risk**; inverted for stress indices |
| Health score | `clip((mean − vmin) / (vmax − vmin), 0, 1) × 100` over the primary index |
| Score labels | `≥ 70` healthy · `≥ 45` moderate · else poor |
| Per-index status | `good` if `mean ≥ healthy_threshold`; `moderate` if `≥ 0.6 × threshold`; else `poor` (inverted for stress indices) |
| Flag: low chlorophyll | NDRE/GCI/RECI status `poor`/`moderate` → possible N deficiency |
| Flag: waterlogging | NDWI mean `> 0` → possible standing water |
| Flag: senescence | PSRI status `poor`/`moderate` |
| Flag: low vigor | NDVI/SAVI/OSAVI status `poor` |
| Flag: patchiness | NDVI `std > 0.18` → uneven growth |

## B.3 API reference

- **`POST /api/preprocessing/analyze-images`** — multipart band images (field
  names carrying the band, or a `band_map`; parts named `panel*` are used for
  calibration). Returns the report, risk distribution, action plan and preview
  URLs.
- **`GET /api/preprocessing/health`** — capabilities (advertises the indices).
- **`GET /api/preprocessing/output/<path>`** — serves generated preview/risk-map
  images.

---

# Vegetation Indices — introduction & significance

## What a vegetation index is

A **vegetation index** is a simple arithmetic combination of surface
**reflectance** in two or more spectral bands, designed to amplify a property of
the canopy (greenness, chlorophyll, water, or stress) while cancelling out
nuisance effects like brightness, soil background, or atmosphere.

The physical basis: healthy leaves **absorb** strongly in the red band (for
photosynthesis) and **reflect** strongly in the near-infrared (NIR, from internal
leaf structure). The bigger the gap between NIR and red, the more vigorous,
green biomass is present. Most indices are variations on measuring that gap while
correcting for something (soil, atmosphere, saturation at high biomass, etc.).

Values are computed on reflectance in `[0, 1]`. Many indices use a **normalised
difference** form `(A − B) / (A + B)`, which is bounded to `[-1, 1]` and robust
to overall brightness changes.

## Bands used

| Band | Typical wavelength | Role |
|------|-------------------|------|
| Blue | ~450–495 nm | Atmospheric correction, pigments |
| Green | ~495–570 nm | Peak healthy-leaf reflectance; chlorophyll |
| Red | ~620–700 nm | Chlorophyll **absorption** (photosynthesis) |
| Red-edge | ~700–740 nm | Steep NIR/red transition; sensitive to chlorophyll & stress before visible symptoms |
| NIR | ~760–900 nm | **Reflected** by healthy leaf structure; biomass |

Each index only runs when the bands it needs are present, so RGB-only captures
still get the RGB-family indices.

## Full index reference (21 indices)

`↑` = a high value means a **healthier** canopy (low risk); `↓` = a high value
means **more stress** (high risk).

| Key | Name | Formula | Bands | Category | Health dir. |
|-----|------|---------|-------|----------|:-----------:|
| `ndvi` | NDVI | `(NIR − Red) / (NIR + Red)` | NIR, Red | greenness | ↑ |
| `gndvi` | GNDVI | `(NIR − Green) / (NIR + Green)` | NIR, Green | chlorophyll | ↑ |
| `ndre` | NDRE | `(NIR − RedEdge) / (NIR + RedEdge)` | NIR, RedEdge | chlorophyll | ↑ |
| `rvi` | RVI (SR) | `NIR / Red` | NIR, Red | greenness | ↑ |
| `dvi` | DVI | `NIR − Red` | NIR, Red | greenness | ↑ |
| `savi` | SAVI | `1.5 · (NIR − Red) / (NIR + Red + 0.5)` | NIR, Red | greenness | ↑ |
| `osavi` | OSAVI | `(NIR − Red) / (NIR + Red + 0.16)` | NIR, Red | greenness | ↑ |
| `msavi` | MSAVI2 | `(2N+1 − √((2N+1)² − 8(N−R))) / 2` | NIR, Red | greenness | ↑ |
| `evi` | EVI | `2.5(N−R) / (N + 6R − 7.5B + 1)` | NIR, Red, Blue | greenness | ↑ |
| `evi2` | EVI2 | `2.5(N−R) / (N + 2.4R + 1)` | NIR, Red | greenness | ↑ |
| `arvi` | ARVI | `(N − (2R − B)) / (N + (2R − B))` | NIR, Red, Blue | greenness | ↑ |
| `gci` | GCI (CIgreen) | `NIR / Green − 1` | NIR, Green | chlorophyll | ↑ |
| `reci` | RECI (CIrededge) | `NIR / RedEdge − 1` | NIR, RedEdge | chlorophyll | ↑ |
| `mcari` | MCARI | `((RE−R) − 0.2(RE−G)) · (RE/R)` | RedEdge, Red, Green | chlorophyll | ↑ |
| `psri` | PSRI | `(Red − Green) / RedEdge` | Red, Green, RedEdge | stress | ↓ |
| `sipi` | SIPI | `(NIR − Blue) / (NIR − Red)` | NIR, Blue, Red | stress | ↓ |
| `ndwi` | NDWI (green) | `(Green − NIR) / (Green + NIR)` | Green, NIR | water | ↓ |
| `grvi` | GRVI / NGRDI | `(Green − Red) / (Green + Red)` | Green, Red | rgb | ↑ |
| `vari` | VARI | `(Green − Red) / (Green + Red − Blue)` | Green, Red, Blue | rgb | ↑ |
| `exg` | ExG | `2·Green − Red − Blue` | Green, Red, Blue | rgb | ↑ |
| `tgi` | TGI | `Green − 0.39·Red − 0.61·Blue` | Green, Red, Blue | rgb | ↑ |

## Significance of each index

### Broadband greenness / biomass

- **NDVI — Normalised Difference Vegetation Index.** The workhorse of crop
  remote sensing. Tracks green biomass and canopy vigour; excellent for
  early-to-mid season and for delineating strong vs weak areas. Weakness: it
  **saturates** in dense canopies (stops rising once the canopy is full).
- **RVI (Simple Ratio, NIR/Red).** The oldest vegetation ratio; increases with
  green biomass and leaf-area index. More dynamic range than NDVI at high
  biomass but not bounded, so noisier on sparse cover.
- **DVI — Difference Vegetation Index (NIR − Red).** A raw biomass proxy. Simple
  and sensitive, but because it is not normalised it is affected by brightness
  and soil — best used relatively within one capture.

### Soil-adjusted (suppress bare-soil background)

- **SAVI — Soil-Adjusted VI.** NDVI with a soil-brightness correction term
  (L = 0.5). Designed for **sparse canopy / early season** where bare soil would
  otherwise distort NDVI.
- **OSAVI — Optimised SAVI.** Uses L = 0.16; a good all-round compromise that
  stays stable across different soil types without needing to tune L.
- **MSAVI2 — Modified SAVI.** A self-adjusting soil correction that needs **no
  external L parameter**, so it behaves well from bare soil through to full
  canopy — useful when cover varies a lot across a field.

### Atmospherically / background-resistant

- **EVI — Enhanced VI.** Adds blue-band atmospheric correction and a canopy-
  background term. **Resists saturation in high-biomass** canopies where NDVI
  flattens, giving better contrast in lush crops.
- **EVI2 — Two-band EVI.** An EVI approximation that drops the blue band, so it
  can be used when only red and NIR are available while keeping much of EVI's
  anti-saturation benefit.
- **ARVI — Atmospherically Resistant VI.** Corrects the red band using the blue
  band to cancel haze/aerosol effects — valuable for hazy-day or satellite-style
  captures.

### Chlorophyll / nitrogen

- **GNDVI — Green NDVI.** Swaps red for green; more sensitive to **chlorophyll
  concentration and nitrogen** and stays responsive at higher leaf area than NDVI.
- **NDRE — Normalised Difference Red-Edge.** Uses the red-edge band, which
  penetrates dense canopy. The go-to index for **chlorophyll/N status in mature,
  closed canopies where NDVI has saturated**; often flags nutrient issues before
  they are visible.
- **GCI — Green Chlorophyll Index.** `NIR/Green − 1`; scales with **leaf
  chlorophyll content**, a good proxy for photosynthetic capacity and N.
- **RECI — Red-Edge Chlorophyll Index.** `NIR/RedEdge − 1`; one of the strongest
  **nitrogen indicators**, driving the "investigate nitrogen status" action.
- **MCARI — Modified Chlorophyll Absorption Ratio Index.** Targets the depth of
  chlorophyll absorption; **drops during chlorosis**, so low MCARI signals
  yellowing/pigment loss.

### Stress / senescence

- **PSRI — Plant Senescence Reflectance Index.** **High = senescing or stressed**
  (ratio of carotenoids to chlorophyll rising). Distinguishes healthy green
  tissue from ageing/stressed tissue; used to flag crop maturing early or under
  stress.
- **SIPI — Structure-Insensitive Pigment Index.** Ratio of total carotenoids to
  chlorophyll while cancelling canopy-structure effects. **Rises with pigment
  stress**, useful for detecting disease/nutrient stress independent of biomass.

### Water

- **NDWI (green NDWI, McFeeters).** `(Green − NIR)/(Green + NIR)`. **High = open
  water / waterlogging.** In a crop field, elevated NDWI patches flag standing
  water or drainage/irrigation problems (drives the "check drainage" action).

### RGB-only (no NIR required)

- **GRVI / NGRDI — Green-Red VI.** Greenness from an ordinary RGB camera; a
  practical vigour proxy when no multispectral sensor is available.
- **VARI — Visible Atmospherically Resistant Index.** Adds blue-band correction
  to the green-red contrast, giving a more robust **canopy-cover** estimate from
  RGB.
- **ExG — Excess Green.** `2G − R − B`; a classic segmentation index that cleanly
  **separates green canopy from soil/residue** in RGB imagery.
- **TGI — Triangular Greenness Index.** Approximates **chlorophyll content from
  the visible bands only**, making a rough chlorophyll read possible without NIR.

---

# Running & testing

**Backend**
```bash
cd backend/my_flask_app && ./venv/Scripts/python.exe run.py
```
- Disease scan: `POST http://localhost:5000/api/disease/identify` (multipart image).
- Field analysis: `POST http://localhost:5000/api/preprocessing/analyze-images`.

**Frontend**
```bash
cd Frontend/agri_vision && flutter run
```
On a physical Android device add your LAN IP:
`flutter run --dart-define=API_BASE_URL=http://<your-ip>:5000`.

**Disease-detector smoke check** — the classifier was verified against synthetic
leaves (healthy, chlorosis, leaf-spot, blight, powdery mildew) and via the Flask
test client (health, multipart identify, empty-request guard). See the
per-condition triggers in [§A.5](#a5-classification-rules).

---

*Integrity note: figures in this document describe the algorithms and their
tunable parameters as implemented. No machine-learning accuracy is claimed
because no model is trained on a labelled dataset in the default build; when a
model is supplied via [§A.7](#a7-optional-trained-model-interface), report its
measured test-set metrics there.*
