# Training the leaf-disease model (`/api/disease`)

The Disease tab in the app posts a leaf photo to `POST /api/disease/identify`.
That endpoint works with **no model at all** — it falls back to an OpenCV
colour/lesion heuristic that can tell blight-shaped necrosis from leaf-spot-shaped
speckling from a mildew coating. That fallback is deliberate: the feature has to
work on a laptop in a village with no GPU and no download.

This document is about the other half — training a real CNN so the endpoint can
name *which* disease on *which* crop instead of a category.

Not to be confused with [`CROP_CNN_TRAINING.md`](CROP_CNN_TRAINING.md), which
covers the two **field-scan** models (`AI_CROP_*`, `AI_WEED_*`) that read drone
canopy frames. Same mechanism, different feature, different data — see
[§7](#7-relationship-to-the-field-scan-models).

---

## 1. Quickstart

```bash
cd backend/my_flask_app
python tools/build_leaf_dataset.py          # fetch + merge (~1.8 GB download)
python tools/train_leaf_disease.py          # fine-tune (~2 h on 4 CPU cores)
```

Then add the two lines the trainer prints to `backend/my_flask_app/.env` and
restart:

```
AI_DISEASE_MODEL_PATH=/abs/path/models/leaf_disease.pt
AI_DISEASE_LABELS_PATH=/abs/path/models/leaf_disease_labels.txt
```

Miss a file, or ship a broken one, and the endpoint keeps working on the
heuristic. It never 500s because a model was misconfigured.

---

## 2. The datasets

Both are fetched automatically by `tools/build_leaf_dataset.py`, and both are
auth-free — **no Kaggle API token is needed**. (The PlantVillage data is the
same set published on Kaggle; Mendeley is simply the primary source and does not
require an account.)

| Dataset | Size | Content | Licence |
|---|---|---|---|
| **PlantVillage** — Mendeley `doi:10.17632/tywbtsjrjv.1` | 868 MB | ~55,000 images, 39 classes across 14 crops | CC0 1.0 |
| **PlantDoc** — [`pratikkayal/PlantDoc-Dataset`](https://github.com/pratikkayal/PlantDoc-Dataset) | ~950 MB | ~2,600 images, 27 classes | CC-BY-4.0 |

**Why both.** PlantVillage carries the class coverage, but every image is a
detached leaf on a uniform grey sheet. A model trained only on it learns "leaf
on grey" as part of every class, scores ~99% on its own validation split, and
then does badly on a phone photo of a plant still in the ground. PlantDoc is
small enough that it cannot carry the model alone, but its images are real field
photos — cluttered backgrounds, hands in frame, mixed light — and mixing them in
is what stops the model depending on the grey sheet.

This is the same caveat [`CROP_CNN_TRAINING.md` §6](CROP_CNN_TRAINING.md) raises
for the canopy models, handled here by mixing the data rather than by warning
about it.

### Both downloads are built to survive a bad link

This is not incidental hardening — on a connection that resets every few tens of
MB, the naive approach for each source fails outright:

- **PlantVillage** is one 868 MB file. Mendeley's CDN resets long connections
  (`errno 10054` partway through) and answers Python's default `User-Agent` with
  **403**. It does honour byte ranges, so the fetcher sends a browser-ish UA and
  pulls **12 ranges in parallel**, each resuming independently into its own part
  file. That also happens to be ~10× faster here: one connection sustains about
  4 MB/min, twelve sustain 45.
- **PlantDoc** cannot use ranges at all — GitHub's codeload zip is generated on
  the fly, so there is no `Content-Length` and no range support. `git clone` is
  no better, because the pack is a single stream: a disconnect at 660 MB throws
  away all 660 MB (observed, twice). So it is fetched **file by file** from
  `raw.githubusercontent.com` — 2,579 images of ~370 KB, ten at a time. A
  failure costs one file.

Everything is re-runnable and verifies what it already has: PlantVillage is
checked against its published SHA-256 (`ac343245…90ff0`) and PlantDoc against
each file's size from the tree API. Re-run after an interruption and only the
missing bytes are fetched.

That checksum is not decoration. During development a stale `curl` from an
earlier attempt kept appending to the finished archive; the file was 888 KB too
long and would have unzipped into a subtly wrong dataset. The size check caught
it immediately.

---

## 3. The label space

Both datasets are normalised into one `<crop>___<condition>` id:

```
datasets/leaf_disease/
    tomato___late_blight/
    tomato___septoria_leaf_spot/
    apple___scab/
    corn___gray_leaf_spot/
    potato___healthy/
    not_a_leaf/
```

The mapping is rule-based — a crop token plus a longest-match condition scan —
not a hardcoded table, so `Tomato___Late_blight` (PlantVillage) and
`Tomato leaf late blight` (PlantDoc) land in the same directory. **A folder the
mapper cannot place is reported and skipped, never filed under a best guess.**
Check that mapping before committing to it:

```bash
python tools/build_leaf_dataset.py --report-only
```

### `not_a_leaf` is a real class

PlantVillage ships a set of photos with no leaf in them, and it is worth
keeping. Without it, a model answers a photo of the ground with a confident
disease name. With it, the app can say "point the camera at a leaf" — and on the
model path it is the *model* that makes that call, not the heuristic's
green-pixel test, because a genuine field photo with soil and sky in frame often
fails the latter while the model reads it fine.

### Two answers, one response

The model predicts the specific class; the knowledge base in `app/ai/knowledge_base.py`
holds treatment advice for seven broad conditions. `app/ai/leaf_labels.py` joins
them:

```
tomato___late_blight
    -> shown as   "Tomato Late Blight"        (what it is)
    -> advised as knowledge-base id "blight"  (what to do about it)
```

Both appear in the response, so the app shows the specific finding as the
headline and says the guidance underneath is the general blight guidance:

```jsonc
"disease": {
  "id": "blight",                          // knowledge-base entry (treatment)
  "name": "Tomato Late Blight",            // the model's specific finding
  "crop": "Tomato",
  "label": "tomato___late_blight",         // raw class, traceable to labels.txt
  "category": { "id": "blight", "name": "Blight (early / late blight type)" }
},
"predictions": [                            // ranked, so a near-tie is visible
  { "label": "tomato___late_blight",  "name": "Tomato Late Blight",  "confidence": 0.52 },
  { "label": "tomato___early_blight", "name": "Tomato Early Blight", "confidence": 0.44 }
]
```

Collapsing the model's answer into its category would throw away the crop and
the pathogen. Inventing per-crop treatment text the project does not have would
be worse. Carrying both is the honest option.

A label with no mapping is returned with `"unmapped": true` and routed to the
inconclusive entry — the operator sees "the model said X and we don't know what
X is" rather than a confident wrong diagnosis.

### Severity still comes from the pixels

On both paths, `severity` is measured from the image, not from the classifier.
The class tells you *which* disease; the pixels tell you *how much of the leaf*
it has taken, and that is what decides urgency.

---

## 4. Training

```bash
python tools/train_leaf_disease.py \
    --data datasets/leaf_disease \
    --arch mobilenet_v3_large \
    --epochs 10 \
    --max-minutes 120
```

The defaults target a machine with no CUDA, because that is what this project's
dev box is. The flags that actually change the outcome:

| Flag | Why |
|---|---|
| `--arch mobilenet_v3_large` | ~10× cheaper per image than ResNet-18 at 224px for a couple of points of accuracy — and it is the backbone that can later run on the drone's companion computer. `resnet18` / `efficientnet_b0` are there if you have a GPU. |
| `--img-size 192` | The accuracy/compute knee on CPU. The backend reads the trained size back from the report (see below), so changing it needs no config change. |
| `--freeze-until 0.35` | Freezes the first third of the network. The early blocks learn generic edge and texture filters that a leaf dataset will not improve on, and skipping their gradients is the single biggest CPU saving. `1.0` trains the head only (much faster, several points worse); `0.0` fine-tunes everything. |
| `--max-minutes` | Stops cleanly after the epoch that crosses a wall-clock budget, instead of making you guess an epoch count. |
| `--resume` | Every epoch writes `models/leaf_disease.ckpt`. An interrupted run is not a lost afternoon. |

### Measured throughput

On this project's dev box — 4 CPU cores, no CUDA, `torch==2.12.1+cpu` — a
forward+backward at the default settings runs at:

| Config | Throughput | Full 55k set |
|---|---|---|
| `mobilenet_v3_large` @192px, `--freeze-until 0.35` | **10.4 img/s** | 89 min/epoch |
| `mobilenet_v3_large` @160px, `--freeze-until 0.5` | **20.8 img/s** | 44 min/epoch |

Which is why `--cap` on the builder matters as much as any training flag: the
full merged set is ~58k images, and at 10 img/s a single epoch is an hour and a
half. Capping to 350 images per class gives ~13k images, about 20 minutes an
epoch, and six epochs inside a two-hour budget.

Pick `--epochs` to match what the budget will actually allow rather than
over-setting it and relying on `--max-minutes` to cut the run short: the cosine
schedule anneals over `--epochs`, so a run stopped at 6 of 10 never reaches the
low learning rate where the last point or two of accuracy is won.

The loss is **inverse-frequency weighted** and uses light label smoothing.
Merged public data is lopsided — thousands of healthy tomato leaves against
sixty images of some diseases — and an unweighted model will trade every rare
class away for a better average.

TorchScript export happens on **every validation improvement**, so there is
always a servable model on disk even if the run is killed halfway.

### Outputs

```
models/leaf_disease.pt              TorchScript module
models/leaf_disease_labels.txt      one class per line, in class order
models/leaf_disease_report.json     accuracy, per-class recall, lab/field split
models/leaf_disease.ckpt            resume point (not needed to serve)
```

`leaf_disease_report.json` is not just a record. `app/ai/torch_model.py` reads
`img_size` back out of it at load time, so a model trained at 192 is *served* at
192. That closes the one silent failure this seam had: a size mismatch raises
nothing, it just quietly makes the model worse.

---

## 5. The number to read

Not the headline accuracy. The report scores the two sources separately:

```jsonc
"by_origin": {
  "lab":   { "accuracy": 0.991, "images": 8200 },   // PlantVillage, grey background
  "field": { "accuracy": 0.712, "images": 390 }     // PlantDoc, real photos
}
```

**`field` is what predicts how the app behaves**, because a farmer photographs a
leaf on the plant, not on a sheet of paper. A run where `lab` is 0.99 and `field`
is 0.45 has learned the background, not the disease.

`per_class_recall` matters for the same reason: a model that answers "healthy"
to everything still posts a respectable average, and is worse than useless to
someone looking for the diseased 15%. `worst_confusions` lists the ten pairs it
mixes up most — expect the two blights and the several leaf spots near the top,
because they genuinely are hard to separate in one frame.

---

## 6. Verifying it is live

```bash
curl http://localhost:5000/api/disease/health
```

```jsonc
{
  "engine": "model",
  "model": { "file": "leaf_disease.pt", "classes": 33, "input_size": 192, "labels": [...] }
}
```

`"engine": "heuristic"` with `"model": null` means the env vars are not set, the
paths are wrong, or the file failed to load — check the backend log, which says
which. Per-scan, `source` in the response says which engine answered, and every
history row stores it, so a season's records stay comparable even if a model is
added halfway through.

---

## 7. Relationship to the field-scan models

Three optional models, one mechanism (`app/ai/torch_model.py`):

| Env pair | Feature | Input | Trainer |
|---|---|---|---|
| `AI_DISEASE_*` | `/api/disease` — a phone photo of one leaf | close-up leaf | `tools/train_leaf_disease.py` |
| `AI_CROP_*` | `/api/fieldscan` — crop disease in a drone frame | canopy from altitude | `tools/train_crop_cnn.py` |
| `AI_WEED_*` | `/api/fieldscan` — weed species | canopy from altitude | `tools/train_crop_cnn.py` |

**Do not point `AI_CROP_MODEL_PATH` at `leaf_disease.pt`.** The files are
interchangeable in format and not in meaning: this model is trained on close-up
single leaves and a canopy frame from 30 m is a different image entirely. The
field-scan models want the MP-crop data described in
[`CROP_CNN_TRAINING.md`](CROP_CNN_TRAINING.md) §3.

---

## 8. Serving it in production

The backend has **no torch dependency on purpose**. Look at the root
`requirements.txt`: it is the file Railpack installs from, and the note at the
top records that a torch/ultralytics pip-freeze used to live there and was
removed. Every model in this project is optional over a heuristic precisely so
the deployed image can stay small.

That has a consequence worth stating plainly: **training a model does not by
itself make the deployed backend use it.** Locally it will serve (the dev venv
has torch). On Railway, `/api/disease/health` will keep reporting
`"engine": "heuristic"` — not because anything is broken, but because torch is
not installed there.

To serve the model on a host, install the extra layer explicitly:

```bash
pip install -r requirements.txt -r requirements-model.txt
```

and ship `leaf_disease.pt`, `leaf_disease_labels.txt` and
`leaf_disease_report.json` (the report carries the input size) to a path the
env vars point at. Budget roughly 250 MB of image size for the CPU wheels.

Whether that trade is worth it is a deployment decision, not a code one. The
heuristic is a working feature, and the endpoint's contract is identical either
way — only `source` in the response changes.

---

## 9. What to expect, honestly

- **PlantVillage's 14 crops are not MP's 8 crops.** Tomato, potato, corn and
  soybean overlap usefully. Wheat, chickpea, mustard, cotton and pigeonpea — the
  crops `app/ai/crop_kb.py` is actually built around — are **not in this dataset
  at all**. For those, the model has no class to answer with, and the honest
  path is collecting local data (see `CROP_CNN_TRAINING.md` §4: the app is
  already the collection tool).
- **A photo shows a pattern, not a pathogen.** Early and late blight are a
  coin-flip in some frames; fusarium wilt and drought stress often are not
  separable at all. That is why the response carries the runner-up and why every
  answer ships with a disclaimer.
- **Neither dataset was collected in Madhya Pradesh.** Lighting, cultivars and
  disease pressure all differ. Treat this model as a strong starting point for
  transfer learning on local imagery, not as a finished product.
