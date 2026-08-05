# Live capture → K-means spray prescription → weed & disease scan

Three modules that form one chain, from the drone's cameras to a valve opening
over the part of the field that actually needs it.

```
  multispectral rig ─┐
                     ├─► /api/capture ─┬─► /api/spray     K-means → zones → options
  RGB IP camera ─────┘                 │                  → operator chooses
                                       │                  → spray mission
                                       └─► /api/fieldscan  weeds + crop disease (CNN)
```

## 1. Capture — `/api/capture`

The backend holds the camera connections, not the phone: the drone's IP cameras
live on the aircraft's own network, which the operator's handset may not be on.

Register one camera per multispectral band, plus the RGB camera:

```bash
curl -X POST localhost:5000/api/capture/cameras -H 'Content-Type: application/json' \
  -d '{"name":"NIR band","role":"multispectral","band":"nir","url":"rtsp://192.168.1.51:554/stream1","fov_deg":62}'
```

Supported URLs: `rtsp://…`, an MJPEG stream, an HTTP snapshot endpoint
(`…/snapshot.jpg`), or a local file for bench testing.

| Endpoint | What it does |
|---|---|
| `POST /cameras` `GET /cameras` `DELETE /cameras/<id>` | the registry |
| `POST /cameras/test` | probe a feed — answers 200 either way, because "unreachable" is information |
| `POST /shoot` | trigger **every** enabled camera at once |
| `POST /upload` | store frames the app already holds (card-recording rigs, bench testing) |
| `GET /frames` `GET /sessions` | history, grouped into shots |

Two things worth knowing:

- **All feeds are pulled in parallel.** Grabbing five RTSP streams one after
  another spreads a "shot" over seconds of forward flight, and the bands no
  longer describe the same patch of ground.
- **Frames are geotagged from live MAVLink telemetry** at the moment the
  shutter fires, before the network round-trips. No fix means the shot can
  still be analysed but cannot become spray waypoints — and it says so.

Nothing is seeded. A camera that does not exist cannot take a picture.

## 2. Spray prescription — `/api/spray`

```bash
curl -X POST localhost:5000/api/spray/prescribe -H 'Content-Type: application/json' \
  -d '{"shot_id":"shot_1723…","k":3,"fov_deg":62}'
```

What happens inside: reflectance → vegetation index (NDVI by default) →
**K-means (k=3)** → clusters ordered by vigour and mapped to *severe /
moderate / healthy* → morphological cleanup → connected components become
sprayable **patches** → each patch georeferenced through a nadir pinhole model.

Why clustering rather than an NDVI threshold: a threshold that is right for
irrigated wheat in Vidisha in January is wrong for rainfed soybean in
Chhindwara in August. Clustering asks "which parts of *this* field are worst
relative to the rest of it", which is the question variable-rate spraying needs
answered. The trade-off is that a uniformly healthy field still produces a
"worst" cluster — so the response carries `low_contrast: true` and a note when
the spread between cluster means is too small to act on.

The response contains three costed options:

| Option | Treats | Typical saving |
|---|---|---|
| `severe_only` | the worst cluster | largest |
| `severe_moderate` | worst at full rate, moderate at a reduced rate | middling |
| `blanket` | everything — the baseline, shown so the saving is visible | 0% |

Then, and only then:

```bash
# What would be flown. Nothing is sent.
curl -X POST localhost:5000/api/spray/prescriptions/7/plan -d '{"option":"severe_only"}'

# Send it to the aircraft. start=true is what opens a valve.
curl -X POST localhost:5000/api/spray/prescriptions/7/execute -d '{"option":"severe_only","start":true}'

# In-flight abort: closes the valve, then holds.
curl -X POST localhost:5000/api/spray/stop
```

### Spray hardware (`.env`)

How the pump is actuated is rig-specific, so it is configuration:

```env
SPRAY_MECHANISM=sprayer        # sprayer | servo | relay
SPRAY_SERVO_CHANNEL=9          # servo mechanism only
SPRAY_SERVO_OFF_PWM=1000
SPRAY_SERVO_ON_PWM=2000
SPRAY_RELAY_NUMBER=0           # relay mechanism only
SPRAY_SWATH_M=3.0              # nozzle width on the ground
SPRAY_ALTITUDE_M=3.0           # spraying is low — not survey height
SPRAY_SPEED_MS=3.0
```

| Mechanism | MAVLink command | Variable rate? |
|---|---|---|
| `sprayer` | `MAV_CMD_DO_SPRAYER` (216) | No — ArduPilot's pump rate is a vehicle parameter, not a mission argument |
| `servo` | `MAV_CMD_DO_SET_SERVO` (183) | **Yes** — PWM is interpolated between closed and open |
| `relay` | `MAV_CMD_DO_SET_RELAY` (181) | No |

This distinction is surfaced, not hidden. On an on/off rig the moderate zones
are sprayed at full rate and the saving comes only from the ground that is
skipped — and `/plan` re-costs the option against the rig's actual hardware
before the number is shown to the farmer.

The mission itself brackets each patch: approach with the valve **shut**, open
it, fly a boustrophedon across the patch one swath apart, close it. The run
starts with an explicit valve-off, so a pump left open by a previous flight
cannot spray the whole transit.

### Accuracy caveats

Georeferencing assumes a nadir camera over level ground, at the altitude the
autopilot reports (height above *launch*, not above the canopy). With no
heading it falls back to north-up. Every response carries these in
`coverage.assumptions`, and the app asks the operator to confirm before
anything opens a valve.

## 3. Weed & disease scan — `/api/fieldscan`

The survey pass says *where* the field is stressed; a low, slow pass with the
RGB camera says *why*.

```bash
curl -X POST localhost:5000/api/fieldscan/session \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"sess_20260805_101500_ab12cd","crop":"soybean"}'
```

**Weeds.** The hard part is deciding which plants are the crop. A sown crop
grows in lines and weeds do not, so the detector segments vegetation (Excess
Green + Otsu), finds the direction the rows run by searching rotation angles
for the strongest periodicity, and calls the green *between* the rows weed.
Broadcast-sown wheat or transplanted paddy has no row signal; there it falls
back to clustering the vegetation by colour and texture and treating the
minority group as weeds. The response says which method answered
(`inter-row` / `appearance` / `inconclusive`) because that is what the number's
reliability rests on.

**Disease.** Canopy colour and lesion shape are reduced to a (colour, pattern)
signature and matched against the crop's own diseases in `app/ai/crop_kb.py` —
soybean, rice, wheat, gram, maize, mustard, cotton and pigeonpea. The crop is
part of the diagnosis: the same yellowing is yellow rust in wheat and yellow
mosaic in soybean. Heuristic confidence is capped at 0.7, because a canopy
photo narrows the possibilities but does not confirm a pathogen.

Both halves accept a trained CNN instead — see
[CROP_CNN_TRAINING.md](CROP_CNN_TRAINING.md).

Per-frame verdicts are stored with their coordinates, so
`GET /api/fieldscan/summary?session_id=…` re-derives the field-level answer
(weed pressure, disease incidence, **hotspot coordinates**) without re-running
the detector — and those hotspots are what the next targeted spray run is
aimed at.

## In the app

| Screen | Route | What it does |
|---|---|---|
| Drone Capture | `AppRouterNames.capture` | register feeds, capture, hand off to either analysis |
| Targeted Spray | `AppRouterNames.spray` | zones, costed options, confirm & command, stop |
| Weed & Disease Scan | `AppRouterNames.fieldScan` | crop picker, single frame or a whole pass |

`CaptureCubit` is app-scoped so a capture session survives the walk from the
capture screen to the spray screen and back.

## Tests

```bash
cd backend/my_flask_app && venv/Scripts/python -m pytest tests/test_spray.py tests/test_field_scan.py tests/test_capture_routes.py
```
