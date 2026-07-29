# Flying a test mission in simulation (SITL)

AgriVision talks to a flight controller over MAVLink. The same code path works
against a **simulated** aircraft, so you can fly a full survey — plan from KML,
upload waypoints, arm, take off, watch live telemetry on the phone, RTL —
without a drone, a battery, or a field.

This document covers the whole loop: start a simulator, point the backend at
it, and launch from the app's Mission Planning screen.

---

## How the pieces fit

```
 Flutter app                Flask backend                  Vehicle / simulator
 ───────────                ─────────────                  ───────────────────
 MissionPlanningPage        /api/mavlink/connect      ──►   heartbeat
   plan from KML            /api/mavlink/mission      ──►   MISSION_COUNT/ITEM
   Start Mission            /api/mavlink/start        ──►   AUTO + ARM + START
 LiveMissionPage            /api/mavlink/status       ◄──   telemetry @ 4 Hz
   Return Home / Land       /api/mavlink/command      ──►   RTL / LAND
```

The backend owns the MAVLink socket (`app/mavlink/link.py`) — one link per
server process, with a reader thread keeping a telemetry snapshot warm. The app
never speaks MAVLink itself; it polls `/api/mavlink/status` at 2 Hz.

**The app does not care whether the vehicle is real or simulated.** A simulator
is just another MAVLink endpoint.

---

> **Simulator on a second laptop?** See
> [MAVLINK_REMOTE_SETUP.md](MAVLINK_REMOTE_SETUP.md) — the firewall and
> ground-station-id details that only matter across machines are there.

## Step 1 — Start a simulator

Pick whichever you already have. All three end up streaming MAVLink to
UDP port **14550** on your machine, which is what the backend listens on.

### Option A — Mission Planner's built-in SITL (easiest on Windows)

Mission Planner ships a simulator; nothing else to install.

1. Open **Mission Planner**.
2. Go to the **SIMULATION** tab (top toolbar).
3. Pick **Multirotor**, then **Stable** when it offers a firmware channel.
   It downloads the SITL binary the first time (a few MB) and connects itself.
4. Wait until the HUD shows a GPS lock and the status bar reads **Disarmed**
   rather than *No GPS*. Pre-arm checks fail without a 3-D fix.

Mission Planner's SITL sends telemetry out on UDP 14550 by default, so the
backend can listen in alongside Mission Planner itself — both can watch the
same aircraft.

If nothing reaches the backend, add the output explicitly:
**Ctrl+F** → **Mavlink** → set an output to `127.0.0.1:14550`.

### Option B — ArduPilot SITL directly (WSL / Linux / macOS)

```bash
sim_vehicle.py -v ArduCopter --console --map --out=udp:127.0.0.1:14550
```

The `--out` is what matters — it forwards a MAVLink stream to the port the
backend listens on. Add `-L` with a location to start somewhere specific:

```bash
sim_vehicle.py -v ArduCopter --console --map --out=udp:127.0.0.1:14550 -L Bhopal
```

Running SITL under WSL and the backend on Windows? Send it to the Windows host
instead of loopback — `--out=udp:<windows-ip>:14550`.

### Option C — QGroundControl / PX4 SITL

```bash
make px4_sitl gazebo
```

PX4 SITL broadcasts to 14550 already. The mission upload, arm and RTL commands
in this integration are standard MAVLink and work against PX4; the flight-mode
*names* differ (`AUTO.MISSION` vs ArduPilot's `AUTO`), so `start` may need the
mode name adjusted in `link.start_mission()`.

---

## Step 2 — Point the backend at it

The default in `backend/my_flask_app/.env` already matches the setups above:

```
MAVLINK_URL=udpin:0.0.0.0:14550
```

`udpin:` means *the backend listens* and the simulator streams into it — that
is the normal direction for SITL and for MAVProxy's `--out`. Other forms:

| Connection string        | When to use it                                        |
|--------------------------|-------------------------------------------------------|
| `udpin:0.0.0.0:14550`    | Simulator / MAVProxy streaming to us (**default**)     |
| `tcp:127.0.0.1:5760`     | ArduPilot SITL direct, started with `--no-mavproxy`    |
| `udpout:192.168.1.50:14550` | Push to a fixed ground-station address              |
| `COM5` / `/dev/ttyUSB0`  | Real telemetry radio (send `baud`, usually 57600)      |

Start the backend as usual:

```bash
python run.py
```

Check the link is reachable before touching the app:

```bash
curl -X POST http://127.0.0.1:5000/api/mavlink/connect -H "Content-Type: application/json" -d "{}"
```

A good response contains `"connected": true` and a `telemetry` block with a
`mode` (`STABILIZE`, `GUIDED`, …). `"No heartbeat … within 15s"` means the
simulator isn't streaming to that address — recheck Step 1.

> `/connect`, `/start` and `/command` require a signed-in user (JWT), same as
> drone pairing. For curl testing, grab a token from
> `POST /api/auth/signin` and send it as `Authorization: Bearer <token>`.
> `/status` and mission upload work without one.

---

## Step 3 — Fly it from the app

1. Open **Mission Planning**.
2. Tap the **link chip** under the drone status strip (top-left). It reads
   *Connect* while there is no link.
3. Leave the address blank to use `MAVLINK_URL`, or tap the
   **Simulator (SITL / Mission Planner)** preset. Tap **Connect**.
   The chip turns green and shows the vehicle's flight mode.
4. Build the survey: import a `.kml` boundary (the backend plans the lawnmower
   path) or tap waypoints onto the map. Set altitude, speed and line spacing in
   the bottom sheet.
5. Tap **Start Mission** and pick a flight profile.

What happens on that tap:

- the plan is saved to mission history (`planned` → `in_progress`),
- the waypoints are written to the vehicle as a full mission — home, takeoff,
  a speed command, the survey legs, and an RTL to finish,
- the vehicle is switched to **AUTO**, **armed**, and sent **MISSION_START**,
- the Live Mission screen opens showing real telemetry: the drone marker moves
  on GPS position, and altitude / speed / battery come off the link. The badge
  in the top-right shows the flight mode instead of `SIM`.

Watch the same flight in Mission Planner's map at the same time — it is the
same aircraft.

6. **Return Home** sends RTL; **Emergency Land** sends LAND; the back arrow
   puts the vehicle into LOITER/BRAKE. If the autopilot refuses a command you
   stay on the screen and see why, rather than the app pretending it worked.

### With no vehicle connected

Everything still works — the Live Mission screen simulates the flight locally
exactly as it did before, and the badge reads `SIM`. That is the fallback, not
an error.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `No heartbeat on … within 15s` | Simulator not started, or not streaming to 14550. In Mission Planner: Ctrl+F → Mavlink → add output `127.0.0.1:14550`. |
| `pymavlink is not installed` | `pip install -r requirements.txt` in the backend venv. |
| Chip goes amber, "No signal" | Link open but heartbeats stopped — simulator closed or vehicle out of range. |
| `Vehicle rejected arm` | Pre-arm checks. Usually no GPS lock yet: wait for a 3-D fix. The autopilot's reason appears in the link sheet's message list. |
| `Vehicle did not switch to AUTO` | Copter refuses AUTO with no mission loaded. Upload the mission first (the app does this automatically before starting). |
| Address already in use on 14550 | Another GCS already listens there. Have the simulator send to a second port and set `MAVLINK_URL` to it. |
| Mission uploads but the drone doesn't move | Armed but no `MISSION_START`, or throttle at zero in a non-AUTO mode. Re-tap Start Mission. |

---

## API reference

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `GET`  | `/api/mavlink/status` | optional | Link health + telemetry snapshot |
| `POST` | `/api/mavlink/connect` | required | Open the link (`url`, `baud`, `timeout_s`) |
| `POST` | `/api/mavlink/disconnect` | required | Close the link |
| `POST` | `/api/mavlink/mission` | optional | Upload waypoints or a saved `mission_id`; `dry_run` validates only |
| `POST` | `/api/mavlink/start` | required | AUTO + arm + mission start |
| `POST` | `/api/mavlink/command` | required | `arm`, `disarm`, `takeoff`, `rtl`, `land`, `hold`, `auto`, `guided` |

Validate a plan with no vehicle attached at all:

```bash
curl -X POST http://127.0.0.1:5000/api/mavlink/mission -H "Content-Type: application/json" -d "{\"waypoints\":[{\"lat\":23.1918,\"lon\":77.4202},{\"lat\":23.1920,\"lon\":77.4207}],\"altitude_m\":30,\"dry_run\":true}"
```

---

## Code map

| File | Role |
|---|---|
| `app/mavlink/link.py` | The connection: reader thread, telemetry cache, mission upload, commands |
| `app/mavlink/mission_items.py` | Waypoints → MAVLink mission items (pure, unit-tested) |
| `app/services/mavlink_service.py` | Orchestration + mission-history updates |
| `app/api/routes/mavlink_routes.py` | HTTP surface |
| `lib/src/data/mavlink/mavlink_service.dart` | App-side HTTP client |
| `lib/src/ui/cubit/mavlink/mavlink_cubit.dart` | Link state + 2 Hz telemetry polling |
| `lib/src/ui/widget/mission_plan_widgets/mavlink_link_chip.dart` | Link chip + connect sheet |
| `tests/test_mavlink.py` | Mission translation + HTTP surface regression tests |
