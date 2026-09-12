# Flying AgriVision with a real drone

[MAVLINK_SITL.md](MAVLINK_SITL.md) covers the simulator. This is the same loop
with an aircraft that can hurt somebody: what it needs, how it is wired, what
the app refuses to do, and how to work up to a first flight.

Read it end to end before the first time. Everything here has a reason behind
it, and the reasons are the useful part.

---

## 1. What is supported

| | |
|---|---|
| **Autopilot** | **ArduPilot** — ArduCopter 4.x (also Plane/Rover for telemetry and the basic commands) |
| **Protocol** | MAVLink 2 (the default; MAVLink 1 works with `MAVLINK_PROTOCOL=1`) |
| **Vehicles at a time** | One |
| **Spray hardware** | ArduPilot's crop sprayer (`DO_SPRAYER`), a servo valve (`DO_SET_SERVO`) or a relay pump (`DO_SET_RELAY`) |

**PX4 is not flown by the app.** Telemetry works and the screens fill in, but
missions, the launch sequence and the spray commands are written to ArduPilot's
conventions, so the backend refuses them with a message saying so rather than
sending something PX4 would misread. Fly a PX4 aircraft from QGroundControl.

---

## 2. Where the backend has to run

**On a laptop at the field — not on Railway.**

The MAVLink link is a socket or a serial port on the machine the backend runs
on. A cloud server has no telemetry radio, and nothing on the field's own Wi-Fi
can send to it, so `/api/mavlink/connect` refuses there with an explanation
instead of timing out.

```
 telemetry radio ──USB── ground-station laptop ──Wi-Fi── phone
      │                   (backend, this repo)            (the app)
      └─ air radio ── flight controller
```

So, for a flight:

1. Run the backend on the laptop: `python run.py` in `backend/my_flask_app`.
2. Put the phone on the same Wi-Fi (the laptop's hotspot is fine).
3. Point the app at the laptop, not at the cloud, and rebuild it:

   ```
   # Frontend/agri_vision/assets/.env
   BASE_URL=http://192.168.1.5:5000
   ```

   `GET /api/system/links` on the laptop prints the address to use.

The cloud deployment keeps doing everything else — accounts, the advisor, the
scan history. It just cannot see a drone.

---

## 3. Wiring the link

`MAVLINK_URL` in `backend/my_flask_app/.env` sets the default; the app's connect
sheet can override it per flight, and its presets cover all of these.

| Setup | Address | Notes |
|---|---|---|
| Telemetry radio on USB (Windows) | `COM5` | Device Manager gives the number. Baud 57600 for SiK/RFD900. |
| Telemetry radio on USB (Linux) | `/dev/ttyUSB0` | `ls /dev/ttyUSB*`; add yourself to `dialout`. |
| USB cable straight to the flight controller | `COM3` / `/dev/ttyACM0` | Baud is ignored on USB. Bench work only. |
| Wi-Fi bridge, companion computer, Herelink | `udpin:0.0.0.0:14550` | Anything that *streams to* the laptop: an ESP8266 bridge, `mavlink-routerd`, MAVProxy `--out`. |
| Ground station forwarding a copy | `udpin:0.0.0.0:14550` | Mission Planner: Ctrl+F → Mavlink → output to the laptop's IP:14550. |

The radio's speed is on the app's connect sheet as soon as the address is a
serial port. A radio set to 115200 never connects at 57600, and the symptom is
an unhelpful "no heartbeat".

> **Both a ground station and AgriVision on one link?** Set
> `MAVLINK_SOURCE_SYSTEM=254` in `.env`. Mission Planner and QGC both use 255,
> and two stations sharing an id corrupt mission uploads —
> see [MAVLINK_REMOTE_SETUP.md](MAVLINK_REMOTE_SETUP.md).

### The link picks the flight controller, not the first thing that talks

A real aircraft's link carries heartbeats from more than the autopilot: a
MAVLink camera, a gimbal, a companion computer, and any other ground station
watching. The backend waits for a heartbeat that is actually an autopilot and
locks onto that one; telemetry from anything else is ignored. If it only ever
hears the others, the error says so.

---

## 4. Flight controller settings

Set these in Mission Planner (Config → Full Parameter List) before flying.

| Parameter | Value | Why |
|---|---|---|
| `SERIALx_PROTOCOL` | `2` | MAVLink 2 on the port the radio is on. |
| `SERIALx_BAUD` | matches the radio | 57 for 57600, 115 for 115200. |
| `RTL_ALT` | clears every tree and wire on the field | Return Home climbs to this first. |
| `WPNAV_SPEED` | the survey speed | The mission also sends a speed command. |
| `WPNAV_RADIUS` | small (100–200 cm) for spraying | How close counts as "reached" — it decides where the valve opens. |
| `FS_GCS_ENABLE` | your choice, knowingly | What the aircraft does if the backend's heartbeat stops. The app will not close the link under an armed drone without asking, but a radio can still fail. |
| `SPRAY_ENABLE`, `SPRAY_PUMP_RATE`, `SPRAY_SPEED_MIN` | per the rig | Only for `SPRAY_MECHANISM=sprayer`. |
| `SERVOn_FUNCTION` | `22` (sprayer pump) or a plain servo | Must match `SPRAY_SERVO_CHANNEL` when using a servo valve. |

Arming is the autopilot's decision, as always: the app does not bypass a
pre-arm check, and force-arming is switched off unless
`MAVLINK_ALLOW_FORCE_ARM=1` is set on the server for bench testing.

### Spray rig settings (backend `.env`)

```
SPRAY_MECHANISM=sprayer      # sprayer | servo | relay
SPRAY_SERVO_CHANNEL=9        # servo rigs: the channel the valve is on
SPRAY_SERVO_OFF_PWM=1000
SPRAY_SERVO_ON_PWM=2000
SPRAY_RELAY_NUMBER=0         # relay rigs
SPRAY_SWATH_M=3.0            # boom width on the ground
SPRAY_ALTITUDE_M=3.0         # spraying is done low
SPRAY_SPEED_MS=3.0
```

Only a servo valve can fly a *reduced* rate. On an on/off rig the moderate
zones are sprayed at full rate, and the saving the app quotes the farmer
already accounts for that.

---

## 5. What the app refuses to do

These are deliberate, and each one is a way a real flight goes wrong:

- **No launch without a pre-flight check.** The sheet before take-off shows the
  3-D GPS fix, the battery, the link and the autopilot, and asks the operator
  to confirm the field is clear, the transmitter is on, and the aircraft is
  secure. Choosing a flight profile no longer arms anything by itself.
- **No launch below a 3-D fix**, or under 30% battery
  (`MAVLINK_MIN_LAUNCH_BATTERY`).
- **No mission above 120 m** above the launch point — India's green-zone limit
  (`MAVLINK_MAX_ALT_M`).
- **No new mission onto an armed aircraft.** ArduPilot accepts one in mid-air
  and carries on from the same item number in the new plan, which is not where
  the operator thinks it is. Land and disarm first.
- **No silent simulation.** If a real launch is refused, the app says why and
  stays on the plan — it does not open an animated flight that looks like the
  real one. If the aircraft was left armed, it offers to disarm it.
- **Return Home, Land and Hold close the spray valve first**, and cancel a
  launch that is still running (its last step would otherwise put the aircraft
  back into AUTO seconds after you asked it to come home).
- **Hold uses BRAKE, not LOITER.** In Copter, LOITER follows the throttle
  stick, and during an autonomous flight that stick is usually at the bottom —
  "hold" would sink the aircraft into the crop.
- **The link is not closed under an armed drone** without a confirmation: it
  would take away the telemetry and the Return Home button of an aircraft that
  is still flying.
- **Signing in is required** to connect, launch, command, or start a spray.

---

## 6. Working up to a first flight

1. **On the bench, no propellers.** Connect the link, watch the telemetry:
   mode, battery, satellites. Move the aircraft and watch the heading change.
2. **Upload a mission with no propellers.** Plan a small block, tap Start
   Mission, and read the pre-flight sheet — then cancel. Check in Mission
   Planner that the waypoints arrived (Plan → Read WPs): home, takeoff, the
   legs, RTL.
3. **Fly it in the simulator first.** [MAVLINK_SITL.md](MAVLINK_SITL.md). The
   app cannot tell a simulator from an aircraft, so everything that works there
   works here.
4. **First real flight:** an empty field, a pilot on the transmitter with a
   finger on the mode switch, a small block, low speed, 15–20 m altitude, and
   an empty spray tank.
5. **First spray:** water in the tank, over the same empty field. Check the
   valve opens over the patches and shuts between them before anything
   chemical goes in.

The transmitter is the safety system. A mode switch on the pilot's radio
overrides anything the app asked for, at any moment.

---

## 7. When something does not work

| Symptom | What it means |
|---|---|
| `No heartbeat on … within 15s` | Nothing is arriving. Radio not bound (check the LEDs), wrong port, wrong baud, or the firewall is blocking the UDP port. Try `python tools/mavlink_listen.py --url <same address>`. |
| `No heartbeat from a flight controller … only N from other devices` | The link works, but the autopilot is not on it — you are hearing a camera, a gimbal or another ground station. Check the radio is wired to a MAVLink port of the flight controller. |
| Connected, but every reading is "—" | Telemetry streams are not coming. The backend keeps re-asking; if it persists, check `SERIALx_PROTOCOL` and the radio's air rate. |
| `This server runs in the cloud…` | The backend is on Railway. Run it on the field laptop (section 2). |
| `Vehicle rejected arm (failed). Vehicle says: PreArm: …` | The autopilot's own check. The text after "Vehicle says" is the thing to fix. |
| `Vehicle refused to switch to AUTO` | Usually no mission loaded, or no position estimate. Upload the mission first; wait for the fix. |
| `Mission upload timed out (12/48 items sent)` | A weak radio link. Move the antennas, lower the air rate, or shorten the mission. |
| `The vehicle is armed. Land and disarm…` | You are uploading a new plan to a flying aircraft. That is not allowed — land first. |
| Valve never opens | `SPRAY_MECHANISM` does not match the rig, or `SPRAY_ENABLE`/`SERVOn_FUNCTION` is not set on the flight controller. Test on the ground with the pump primed with water. |
| Valve opens over the wrong ground | The patches come from the capture's GPS, altitude, heading and camera field of view. Check the camera's `fov_deg` and that frames are geotagged (the flight link must be up *during* the survey). |

---

## 8. Where this lives in the code

| File | Role |
|---|---|
| `app/mavlink/link.py` | The connection: choosing the vehicle, telemetry, commands, mission upload |
| `app/mavlink/mission_items.py` | Waypoints → MAVLink items, with the altitude ceiling |
| `app/spray/mission.py` | The spray mission: valve commands between the passes |
| `app/services/mavlink_service.py` | Guards around the flight: stop actions, cloud refusal, force-arm gate |
| `app/services/spray_service.py` | Prescription → mission → aircraft, and `close_valve` |
| `lib/src/ui/widget/mission_plan_widgets/preflight_sheet.dart` | The pre-flight check |
| `lib/src/ui/widget/drone/flight_controls.dart` | Hold / Resume / Return home / Land, shared by three screens |
| `tests/test_mavlink.py` | The protocol behaviour above, without a vehicle |
