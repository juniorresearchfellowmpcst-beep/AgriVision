# Live drone feed

Watching the drone's camera while it flies, and scanning what it sees as it
covers ground.

This is the *live* half of the capture feature. The other half — press Capture,
store geotagged stills, prescribe a spray from them — is in
[TARGETED_SPRAY.md](TARGETED_SPRAY.md) and is unchanged.

---

## Why the video goes through the backend

The obvious design is for the phone to open the camera's RTSP stream directly.
It does not work here, for two reasons that are both about where things are:

1. **The cameras are on the aircraft's network.** The operator's handset often
   is not. The backend already has to be on that network — the MAVLink link
   runs inside the Flask process — so it is the one component guaranteed to be
   able to reach the camera.
2. **Phones do not speak RTSP.** Playing it in Flutter means a heavy native
   player (`media_kit`, `flutter_vlc_player`) with per-platform setup.

So the backend decodes the camera once and re-serves the picture as
`multipart/x-mixed-replace` — MJPEG — which any HTTP client can render with no
plugin at all. One session to the camera, however many phones are watching.

```
  drone cameras                 ground station (Flask)              handsets
  ┌────────────┐   RTSP/MJPEG   ┌──────────────────────┐   MJPEG   ┌────────┐
  │ RGB cam    │ ─────────────► │  StreamHub           │ ────────► │ phone  │
  │ NIR band   │                │   one reader thread  │ ────────► │ tablet │
  │ red band…  │                │   per camera         │           └────────┘
  └────────────┘                │        │             │
                                │        ▼             │
        MAVLink ──────────────► │  LiveAnalyzer        │
        (telemetry, geotags)    │   samples 1 frame /  │
                                │   3s → weed+disease  │
                                └──────────────────────┘
```

**This is why the deployment runs a single gunicorn worker.** The stream hub
and the MAVLink link are process-local objects with their own threads. Two
workers would mean two links to the same aircraft and two RTSP sessions per
camera. See `gunicorn.conf.py`.

---

## Endpoints

All under `/api/capture`. Cameras are registered with the existing
`POST /api/capture/cameras` — the live endpoints work on whatever is already
in the registry.

| Method | Path | What it does |
| --- | --- | --- |
| `GET` | `/cameras/<id>/stream` | MJPEG relay. Query: `fps` (1–30), `width` (160–1920), `quality` (30–95) |
| `GET` | `/cameras/<id>/frame` | Newest frame as one JPEG. Query: `width`, `quality`, `wait` |
| `GET` | `/live` | State of every feed currently held open |
| `DELETE` | `/cameras/<id>/stream` | Drop the camera session now |
| `POST` | `/cameras/<id>/analyze` | Start scanning the feed |
| `GET` | `/cameras/<id>/analyze` | Latest scan + rolling field-level answer |
| `DELETE` | `/cameras/<id>/analyze` | Stop scanning |
| `GET` | `/cameras/<id>/analyze/frames` | Recent samples, newest last |
| `GET` | `/analyze` | Every running analysis |

`GET /api/capture/health` now reports a `live` block; the app checks it before
offering the video pane, so a new build against an older backend degrades to
stills instead of showing a video pane that can never fill.

### Watching a feed with curl

```bash
curl -s "http://192.168.1.20:5000/api/capture/cameras/1/stream?fps=5&width=640" -o feed.mjpeg
```

### Starting a scan

```bash
curl -X POST http://192.168.1.20:5000/api/capture/cameras/1/analyze -H "Content-Type: application/json" -d '{"crop":"soybean","interval_s":3,"window":40}'
```

The readout comes back from `GET .../analyze`:

```json
{
  "analysis": {
    "running": true,
    "scanned": 27, "skipped": 1, "window": 27,
    "latest": {
      "disease": {"name": "Frogeye leaf spot", "confidence": 0.71, "source": "model"},
      "severity": {"level": "moderate"},
      "weeds": {"weed_coverage": 0.064, "pressure": {"level": "moderate"}},
      "lat": 23.1918, "lon": 77.4202
    },
    "rolling": {
      "frames": 27,
      "summary": "27 frame(s) scanned. Weed cover averages 6% of the ground…",
      "hotspots": [{"lat": 23.1921, "lon": 77.4207, "severity": "high"}]
    },
    "stream": {"state": "live", "fps": 11.8, "viewers": 1}
  }
}
```

---

## Behaviour worth knowing

**A dropped link says so.** The reader reconnects on its own with a backoff
(0.5 s → 8 s). While it is down the relay sends keep-alive parts rather than
going silent, and both the server (`state: reconnecting`) and the app (a dimmed
picture and a "Signal lost" badge) report it. The last good frame is never
presented as current.

**Feeds close themselves.** A stream with no viewers releases the camera after
20 s, so a closed app does not hold an RTSP session for the rest of the flight.

**The buffer is latest-frame-wins.** A phone on bad Wi-Fi falls behind in time,
not in memory, and the frames it does get are the newest ones.

**Live analysis is not recorded.** A live readout is a moving estimate of
whatever was under the camera a second ago. Writing every sample to the scan
history would bury the captures an operator deliberately chose under thousands
of drive-by frames. Recording stays where it was: press Capture.

**Frames are downscaled to 960 px before scanning.** A 4K frame costs seconds
through the weed detector and disease CNN, which would make the readout
describe ground the aircraft has already left. The detectors work on colour and
texture ratios, so the numbers barely move and the latency does.

**Live analysis reads the RGB camera only.** A single multispectral band is a
greyscale image of one wavelength — not what the weed and disease models were
trained on. Bands feed the spray prescription instead.

---

## Sizing the deployment

Each viewer holds one gunicorn worker thread for as long as it watches.

| Setting | Default | Notes |
| --- | --- | --- |
| `LIVE_STREAM_MAX_VIEWERS` | 8 | Relay clients allowed at once; the 9th gets a 503 with a readable message |
| `GUNICORN_THREADS` | 24 | Must stay comfortably above the viewer cap so flight-control endpoints remain answerable |

Bandwidth is roughly `fps × frame size`. At the app's default (12 fps, 960 px
wide, quality 75) one viewer is about **2–4 Mbit/s**. On a weak field link, ask
for less — the query parameters cost the camera nothing, it runs at its own
rate regardless.

---

## Trying it without a drone

Any of these register as a camera and work end to end:

```bash
# a still image on disk — polled like a snapshot endpoint
curl -X POST localhost:5000/api/capture/cameras -H "Content-Type: application/json" -d '{"name":"Bench","role":"rgb","url":"C:/captures/canopy.png"}'

# a phone running an IP-camera app
… -d '{"name":"Phone","role":"rgb","url":"http://192.168.1.33:8080/video"}'

# any public MJPEG test stream, or a local ffmpeg loop:
ffmpeg -re -stream_loop -1 -i clip.mp4 -f rtsp rtsp://localhost:8554/live
```

Rewriting the image file while a stream is open is the quickest way to see the
reconnect and stall behaviour — that is exactly what `tests/test_live_feed.py`
does.

---

## Where the code is

| Concern | File |
| --- | --- |
| Camera held open, reconnect, refcounting | `app/capture/live.py` |
| MJPEG framing | `app/capture/live.py` → `mjpeg_stream()` |
| Sampling + rolling aggregate | `app/services/live_analysis.py` |
| HTTP routes | `app/api/routes/capture_routes.py` |
| Backend tests | `tests/test_live_feed.py` |
| Video widget + multipart parser | `lib/src/ui/widget/capture/mjpeg_view.dart` |
| Screen | `lib/src/ui/view/Capture/live_feed_page.dart` |
| Cubit / service | `lib/src/ui/cubit/livefeed/`, `lib/src/data/capture/live_feed_service.dart` |
| Parser tests | `test/mjpeg_parser_test.dart` |
