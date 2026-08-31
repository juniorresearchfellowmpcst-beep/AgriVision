# The survey flight, and the phone that does not need one

Two ways into the same knowledge base. One flies; one does not.

```
  ┌─ Survey flight ─────────────────────────────────────────────────────────┐
  │ camera mode ──► fly ──► live CNN ──► crop-health report ──► K-means map │
  │  ms | rgb | both        on video     + action + tank plan   ──► spray   │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌─ Scan with Phone ───────────────────────────────────────────────────────┐
  │ pick a crop (or Weeds) ──► photograph the plant ──► diagnosis + product │
  └─────────────────────────────────────────────────────────────────────────┘

  Both end at "More information" ──► the photo and the app's own diagnosis
                                     handed to Gemini, and the farmer keeps asking.
```

---

## 1. Choosing the camera

The camera mode is not a preference. It decides what the flight can find out,
and an operator who picks the wrong one has spent a battery finding out nothing.

| Mode | What it reads | What it can tell you | What it cannot |
| --- | --- | --- | --- |
| `multispectral` | band cameras (red, NIR, …) | *Where* the field is stressed, from a calibrated vegetation index. The stronger of the two maps. | Which disease it is. A single band is a greyscale image of one wavelength, not what the CNN was trained on. |
| `rgb` | the ordinary IP camera | *What* is wrong, named by the CNN on the live video, and roughly where — clustered from the geotagged detections. | Anything a colour camera cannot see. |
| `both` | both rigs | The CNN names the disease while the bands map the stress. The prescription is built from the bands. | — |

`GET /api/survey/capabilities` reports which of the three this rig can fly and
**why not** for the others, so the app disables a mode with its reason attached
rather than letting the operator discover the problem at thirty metres:

```json
{"id": "multispectral", "available": false,
 "reason": "A red and an NIR band camera are both needed to compute a vegetation index (registered: green, blue)."}
```

Registering three green cameras is not a multispectral rig, and the check says
so: the pair that matters is red + NIR.

### Setting the drone for weed detection

`detection_target` is `disease`, `weed` or `both`. It is not a display filter —
`weed` genuinely skips the disease CNN, which roughly halves the per-frame cost.
On a live feed that is the difference between a readout describing where the
aircraft *is* and one describing where it was.

The half that is switched off reports zeroes with `"method": "not_requested"`
rather than being omitted, so nothing downstream can mistake "not measured" for
"clean".

---

## 2. The flight

```bash
curl -X POST localhost:5000/api/survey/runs -H 'Content-Type: application/json' \
  -d '{"camera_mode":"both","detection_target":"both","crop":"soybean","field_name":"Block A"}'
```

For the RGB modes this starts the existing live analyser
(`app/services/live_analysis.py`) against the drone's video feed. It samples one
frame every three seconds, runs weed detection and the crop-disease CNN on it,
and stamps it with where the aircraft was at that moment.

`GET /api/survey/runs/<id>` is the in-flight readout: the verdict on the frame
under the camera a second ago, the rolling answer over the last couple of
minutes, and the stream's own state. A dropped link reports
`state: reconnecting` and the app dims the picture — the failure this screen
most has to avoid is a frozen "healthy" while the aircraft crosses the worst
part of the block.

On a multispectral run there is nothing to stream, so the operator triggers
shots instead: `POST /api/survey/runs/<id>/shoot` fires every band camera at
once, filed under the run's own session. Taking the session id from the run
rather than the request is the point of having a run at all — a stale screen
cannot file a shot against the wrong survey.

### Live samples are held in memory, not recorded

The analyser keeps every sample it has taken (capped at ~3 hours of flight) so
the summary can be built over the whole pass rather than the last two minutes.
Nothing reaches the scan history: a live readout is a moving estimate, and
writing thousands of drive-by frames into the history would bury the captures an
operator deliberately chose.

---

## 3. The report

`POST /api/survey/runs/<id>/finish` ends the pass and produces, in order of what
they cost:

**Crop health** — one number, 0–100, and one sentence. Deliberately blunt: its
value is not precision, it is that two flights over the same block a week apart
are comparable, which is what a farmer actually asks. A pass that scanned
nothing gets `null`, not zero — zero reads as a dead crop. Below eight frames
the answer is flagged `confident: false`, because that is a summary of a few
seconds of hovering, not of a block.

**What was found** — the existing field-scan aggregate: conditions with their
frame share, weed pressure, and hotspot coordinates.

**The treatment** — new, and the gap this whole feature exists to close. The app
could already tell a farmer they had yellow mosaic and then stopped one question
short of the only one that matters. `app/ai/treatment_kb.py` answers it: which
product, at what dose per acre, in how much water, at which crop stage, and how
many days before harvest.

Three things that module refuses to do:

* **Pick a brand.** Products are named by active ingredient and formulation,
  because that is what the label says and what a dealer can match.
* **Silently mix.** A survey finding a fungal disease, an insect and heavy weeds
  produces **three tanks**, and says so. A fungicide and an alkaline-sensitive
  insecticide in one load is a wasted flight.
* **Promise a cure.** A virus has no spray that treats it. Yellow mosaic, cotton
  leaf curl and sterility mosaic target the *vector* instead and say so;
  loose smut and the soil-borne wilts answer `sprayable: false` with what to do
  instead, because flying a fungicide at them cannot work.

**The action plan** — the scan's agronomy advice, with the chemical decision
attached to it. Rows carrying a `product` are the step that used to be missing
between "you have rust" and a flight.

---

## 4. The map

Both camera modes end at K-means, but over different raw material.

**Multispectral** — `app/spray/prescription.py`, unchanged: reflectance →
vegetation index → K-means → severe / moderate / healthy → sprayable patches.
See [TARGETED_SPRAY.md](TARGETED_SPRAY.md).

**RGB** — `app/spray/hotspot_zones.py`, new. A plain IP camera produces no index
to cluster; what it produces is a trail of geotagged frames each carrying a CNN
verdict. So the clustering runs over the detections themselves: position in
metres plus a severity score, into zones, ordered worst-first, and emitted in
**exactly the prescription schema** — which is why the existing
`/api/spray/prescriptions/<id>/plan` and `/execute` fly it without knowing which
camera the field was surveyed with.

The severity score combines disease and weeds by taking the **worse** of the
two, not the average. A frame clean of weeds but carrying high-severity blast is
worth spraying, and averaging would dilute it into the moderate band where it
might be skipped.

Three limits, all reported rather than hidden:

* **A detection is a point, not an outline.** A cluster's radius comes from how
  far its member frames spread plus one frame's ground footprint, floored at
  half a swath. It is a spray footprint, never the true edge of an infection.
* **Unlocated frames cannot be sprayed.** They still count towards the health
  summary; `skipped_no_fix` says how many.
* **Few detections make a poor map.** Below six located frames the module does
  not pretend to cluster — one patch per detection, and a note saying so.

A uniform field still produces a "worst" cluster, so `low_contrast: true` rides
on the response and the app shows it above the spray button. That is the failure
mode that quietly sends a drone out to spray a healthy block.

---

## 5. The spray

`POST /api/survey/runs/<id>/authorise` is the only path from a report to an open
valve, and it needs **three separate things** in its body:

```json
{"tank_filled": true, "tank_litres": 10, "authorised_by": "Ramesh",
 "spray_authorised": true, "option": "severe_only", "start": true}
```

That is not ceremony. Each is a different mistake:

1. **`tank_filled`** is a statement about the aircraft. Without it the drone
   flies the entire prescription pumping air and the operator finds out
   afterwards.
2. **`spray_authorised` + `authorised_by`** is a statement by the farmer,
   recorded with the run — a chemical application is a record somebody may need
   later.
3. **`start`** is what actually launches. The field being clear is not something
   the app can check, so the last flag is left to the person who can see it.
   Without it the mission is uploaded and waits.

The endpoint refuses when the tank is not confirmed, when the run was never
summarised, when there is no prescription, and when the survey found nothing a
spray would help. **A failed upload keeps the authorisation**: the farmer did
fill the tank and did give permission, and making them do it again because the
radio dropped would be its own small cruelty.

Both spellings are routed (`/authorise` and `/authorize`) — a 404 over an
-ise/-ize is a bad reason for a farmer to be unable to spray.

---

## 6. Scan with Phone

`/api/crops` — the drone-free path, and the one most farmers will use most days.
A farmer standing in a field with a suspicious leaf does not want to charge a
battery and fit a camera; they want to point their phone at it.

| Endpoint | What it does |
| --- | --- |
| `GET /api/crops?month=8` | the picker grid; `month` marks and sorts by what is in the ground now |
| `GET /api/crops/<crop>` | every disease that crop gets here, each with its treatment |
| `GET /api/crops/<crop>/diseases/<id>` | one disease in full |
| `GET /api/crops/weeds?crop=wheat` | the weeds, and the herbicides safe over that crop |
| `POST /api/crops/scan` | one photo → diagnosis + treatment |

The **Weeds** tile sits in the same grid as the crops, because that is where a
farmer looks for it — but it is served as `weeds_option`, kept out of the `crops`
array, so nothing iterating crops to run a disease model is ever handed a
non-crop.

Two deliberate asymmetries with the drone path:

* **A phone scan never becomes a spray run.** One leaf says nothing about where
  in the block the problem is, and a map built from a single point would be a
  map of where the farmer happened to be standing. The result screen says this
  and offers a survey instead of a disabled spray button.
* **No crop means no herbicide.** Weed pressure can be measured without knowing
  the crop; a herbicide cannot be recommended without it, because the product
  that clears a wheat field will kill a soybean one. That is the one
  recommendation in the knowledge base that would reliably destroy a field, so
  it is refused with an explanation rather than guessed.

---

## 7. More information — the crop advisor

`/api/advisor` hands the photo and the app's own diagnosis to Gemini so the
farmer can keep asking: is it safe to spray at flowering, what if it rains
tomorrow, can I use what is already in the shed.

**This is the one feature that needs internet**, and the one place a field
photograph leaves the ground station. It is therefore opt-in and off by default:

```env
# backend/my_flask_app/.env  (gitignored — never commit a key)
GEMINI_API_KEY=...
# GEMINI_MODEL=gemini-flash-latest   # optional; leave unset
```

On a deployed backend set the same variable in the host's own environment
(Railway → the service's **Variables** tab), not in the repo.

**Leave `GEMINI_MODEL` unset.** The default is the alias `gemini-flash-latest`,
which follows whatever the current flash model is. A pinned id rots:
`gemini-2.5-flash` was the default here until Google retired it for new keys,
and the feature answered 404 on a ground station nobody was watching. When the
model *is* wrong the error names `GEMINI_MODEL` and passes Google's own "use X
instead" message through, because that is a one-line fix for an admin.

The key travels in an `X-goog-api-key` header rather than `?key=` — query
strings end up in proxy logs and crash reports, and both forms authenticate
equally.

The flash endpoint answers `503 UNAVAILABLE` ("currently experiencing high
demand") often enough that one attempt is not a fair test of whether the
advisor works — in testing the third try succeeded within four seconds. So
transient statuses (429, 5xx) are retried up to three times with a short
backoff, bounded so the screen is never held open. A 403 or a 404 is not
retried: those answer the same way forever, and retrying only makes the error
slower to arrive.

With no key the endpoints answer 503 with a clear message and the app hides the
button entirely — a button that exists and fails when tapped is worse than one
that is absent, especially on a ground station that has no internet by design.

The model is told to **build on** the CNN's answer and to say so plainly if it
disagrees, rather than quietly substituting a different diagnosis. A farmer
shown two disease names with no explanation is worse off than before they asked.

The photo is sent with the first question only; after that the model has seen it,
and re-uploading it every turn would make each follow-up as slow as the first.

---

## In the app

| Screen | Route | What it does |
| --- | --- | --- |
| Survey Flight | `AppRouterNames.survey` | camera mode + crop + target → in-flight readout → report → authorise & spray |
| Scan with Phone | `AppRouterNames.cropScan` | the crop grid, then a photo |
| Crop Advisor | pushed with its own cubit | one conversation per scan |

`SurveyCubit` and `CropCubit` are app-scoped. For the survey that is not an
optimisation: the scan runs on the *server*, so leaving the screen stops the
polling rather than the flight, and coming back adopts the run that kept going.
`AdvisorCubit` is deliberately **not** app-scoped — one conversation belongs to
one scan, and carrying it across to a different field would let the advisor
answer confidently about the wrong crop.

## Tests

```bash
cd backend/my_flask_app && venv/Scripts/python -m pytest tests/test_survey.py -q
cd Frontend/agri_vision && flutter test test/survey_entity_test.dart
```

Most of `test_survey.py` is about the ways `/authorise` is supposed to *refuse*,
and about the treatment knowledge: a recommendation that names a fungicide for a
virus, or a herbicide without knowing the crop, would be worse than no
recommendation at all.
