# Training the crop-disease and weed CNNs (Madhya Pradesh crops)

AgriVision's field scan (`/api/fieldscan`) runs **without any model**: weeds are
found from crop-row geometry and disease is matched from a canopy colour/pattern
signature, both in plain OpenCV. That is deliberate — the feature has to work on
a laptop in a village with no GPU and no download.

This document is about the other half: replacing either heuristic with a trained
CNN when you have the data for it.

```
AI_CROP_MODEL_PATH   / AI_CROP_LABELS_PATH    crop-disease classifier
AI_WEED_MODEL_PATH   / AI_WEED_LABELS_PATH    weed-species classifier
```

> **Looking for the leaf-photo model instead?** The Disease tab
> (`/api/disease`, `AI_DISEASE_*`) is a different feature with different data —
> a close-up of one leaf rather than a canopy frame from altitude. It has its
> own trainer and its own datasets: see
> [`LEAF_DISEASE_MODEL.md`](LEAF_DISEASE_MODEL.md). The two model files are
> interchangeable in *format* and not in *meaning*; do not point `AI_CROP_MODEL_PATH`
> at a leaf model.

Set the pair in the backend `.env`, restart, and `/api/fieldscan/health` reports
`"engines": {"disease": "model", "weed": "model"}`. Miss a file, or ship a broken
one, and the endpoint keeps working on the heuristic — it never 500s because a
model was misconfigured.

## 1. Which crops, and why these

MP's cultivated area is dominated by a short list, so that is what the knowledge
base in `app/ai/crop_kb.py` covers and what the model should be trained on:

| Crop | Season | Where in MP | Diseases the app knows |
|---|---|---|---|
| Soybean | kharif | Malwa plateau, Narmada valley | yellow mosaic, charcoal rot, anthracnose, rust, girdle beetle |
| Rice | kharif | Balaghat, Seoni, Mandla, Rewa | blast, bacterial leaf blight, brown spot, sheath blight |
| Wheat | rabi | statewide; Sharbati belt in Sehore/Vidisha | yellow rust, brown rust, powdery mildew, loose smut |
| Chickpea (gram) | rabi | black-soil districts | fusarium wilt, ascochyta blight, botrytis grey mould, pod borer |
| Maize | kharif | Chhindwara, Betul | turcicum blight, common rust, fall armyworm |
| Mustard | rabi | Bhind, Morena, Gwalior | alternaria blight, white rust, aphid |
| Cotton | kharif | Nimar — Khargone, Khandwa, Barwani | leaf curl virus, bacterial blight, alternaria spot |
| Pigeonpea (tur) | kharif | statewide intercrop | fusarium wilt, sterility mosaic |

## 2. Dataset layout

`tools/train_crop_cnn.py` reads torchvision's `ImageFolder` — one directory per
class:

```
datasets/crop_disease/
    healthy/
    soybean_yellow_mosaic/
    soybean_charcoal_rot/
    wheat_yellow_rust/
    wheat_brown_rust/
    rice_blast/
    rice_brown_spot/
    gram_wilt/
```

**Name the folders after the ids in `app/ai/crop_kb.py`.** The label mapper in
`app/ai/crop_model.py` will handle a public dataset's own naming
(`Wheat___Yellow_Rust`, `BrownSpot`, `leaf_blast`) by normalising and
token-matching it, and it scopes the match to the crop being scanned so a bare
`rust` resolves to yellow rust under wheat and soybean rust under soybean. But an
exact id needs no guessing, and a label the mapper cannot place is surfaced to the
operator as *unmapped* rather than shown as a diagnosis.

Same idea for weeds, using the ids in `app/ai/weed_kb.py`:

```
datasets/weeds/
    phalaris_minor/
    echinochloa/
    cyperus_rotundus/
    chenopodium_album/
    parthenium/
    crop/          # the crop itself — the model needs the negative class
```

## 3. Public datasets to start from

None of these were collected in Madhya Pradesh, and that matters (see §6). They
are a starting point for transfer learning, not a substitute for local data.
Check each one's licence before using it in anything you ship.

| Dataset | Covers | Where it lives | Watch out for |
|---|---|---|---|
| PlantVillage | 38 classes incl. soybean, maize, tomato, potato | Mendeley Data; `spMohanty/PlantVillage-Dataset` on GitHub | Single leaves on a **uniform lab background**. A model trained only on this collapses on real canopy frames. |
| Rice Leaf Diseases | bacterial leaf blight, brown spot, leaf smut | UCI Machine Learning Repository | Very small (~120 images). Useful only combined with others. |
| Rice Leaf Disease Image Samples (Sethy et al.) | blast, brown spot, bacterial blight, tungro | Mendeley Data | Field-captured — much closer to what the drone sees. |
| CGIAR Computer Vision for Crop Disease | wheat leaf rust, stem rust, healthy | Zindi competition archive | Ethiopian fields, phone photos. Good rust variety. |
| Wheat Leaf Dataset | healthy, septoria, stripe rust | Mendeley Data | Small but field-realistic. |
| Weed Detection in Soybean Crops (dos Santos Ferreira et al.) | soil, soybean, grass, broadleaf — ~15k images | Mendeley Data | **The most directly useful weed set** — Brazilian soybean, and the four-class split matches how this app thinks. |
| DeepWeeds | 9 Australian rangeland weed species | `AlexOlsen/DeepWeeds` on GitHub | Wrong species for MP, but excellent for pretraining "weed-shaped thing vs crop". |
| CottonWeedID15 | 15 weed species in US cotton | Public research release | Some genera overlap MP (*Cyperus*, *Digera* relatives). |

Species that genuinely have no good public dataset — *Phalaris minor* in wheat,
gram wilt, soybean girdle beetle — are exactly the ones worth collecting locally,
and the app is already the collection tool: every `/api/fieldscan/analyze` frame
is stored with its verdict and coordinates.

## 4. Collecting your own from the drone

The highest-value dataset for this app is the one the aircraft takes itself,
because it matches deployment conditions exactly.

1. Fly the **low-pace mission** (low altitude, slow, RGB camera) and capture
   frames — `POST /api/capture/shoot` stores each one geotagged.
2. Walk the same block and record the ground truth per spot.
3. Export the frames from `instance/captures/<session>/` and sort them into class
   directories.
4. Aim for **at least 300–500 images per class** before expecting a model to beat
   the heuristic, and cover both a morning and an afternoon flight — canopy
   colour shifts a lot with sun angle, and a model trained only on 9 a.m. light
   will disagree with itself at 2 p.m.

## 5. Training

```bash
pip install torch torchvision

python tools/train_crop_cnn.py \
    --data datasets/crop_disease \
    --task disease \
    --arch resnet18 \
    --epochs 15
```

```bash
python tools/train_crop_cnn.py \
    --data datasets/weeds \
    --task weed \
    --arch mobilenet_v3_large \
    --freeze-backbone
```

Notes on the flags that actually change the outcome:

- `--arch mobilenet_v3_large` if the model will ever run on the drone's
  companion computer; `resnet18` is the safe default on a server.
- `--freeze-backbone` trains the classifier head only. On a small dataset
  (< ~200 images/class) this usually beats full fine-tuning, and it is several
  times faster.
- The loss is **inverse-frequency weighted**. Field datasets are lopsided —
  `healthy` outnumbers every disease — and an unweighted model reaches 85%
  accuracy by answering "healthy" to everything, which is worse than useless to
  a farmer looking for the other 15%. The per-class recall in the generated
  `*_report.json` is the number to read, not the headline accuracy.

Output:

```
models/crop_disease.pt            TorchScript module
models/crop_disease_labels.txt    one class name per line, in class order
models/crop_disease_report.json   accuracy + per-class recall
```

Then in `.env`:

```
AI_CROP_MODEL_PATH=/abs/path/models/crop_disease.pt
AI_CROP_LABELS_PATH=/abs/path/models/crop_disease_labels.txt
```

## 6. What to expect, honestly

- **Lab-background datasets do not transfer to canopy frames.** A PlantVillage
  model reports ~99% on its own validation split and falls apart on a drone
  frame, because it learned "leaf on grey background" as part of every class.
  Mix in field imagery, or use PlantVillage only for the backbone warm-up.
- **A canopy photo shows a pattern, not a pathogen.** Yellow rust and brown rust
  are separable by pattern; fusarium wilt and drought stress often are not. This
  is why `scan_frame` caps heuristic confidence at 0.7 and every response carries
  a disclaimer, and why the model path returns the runner-up class as well.
- **Sterility mosaic in pigeonpea is the case imagery alone will miss** — the
  canopy stays green and healthy-looking and simply never sets pods. High NDVI,
  zero yield. Ground-truthing is not optional.
- The weed heuristic's `method` field says how it decided: `inter-row` (row
  geometry, reliable), `appearance` (colour/texture clustering, indicative), or
  `inconclusive`. A trained model does not remove the need for that distinction —
  it changes which weed is named, not whether the plant was a weed.

## 7. Verifying the model is live

```bash
curl http://localhost:5000/api/fieldscan/health
```

```json
{ "engines": { "disease": "model", "weed": "heuristic" } }
```

Per-scan, the response says which engine answered — `disease.source` is `"model"`
or `"heuristic"` — and every scan row stores it, so a season's records stay
comparable even if a model is added halfway through.
