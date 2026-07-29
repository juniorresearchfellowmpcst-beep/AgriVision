# Connecting Mission Planner on a second laptop

Running the AgriVision backend + app on one laptop, and Mission Planner's
ArduPilot simulator on another, both on the same Wi-Fi.

```
   LAPTOP A  (yours, 192.168.1.3)              LAPTOP B  (Mission Planner)
   ┌────────────────────────────┐              ┌──────────────────────────┐
   │  Flask backend  :5000      │              │  Mission Planner         │
   │  listening for MAVLink     │◄─────────────┤  + SITL simulated drone  │
   │  UDP :14550                │  UDP 14550   │  outputs telemetry       │
   │  Flutter app               │              │                          │
   └────────────────────────────┘              └──────────────────────────┘
```

Laptop B **pushes** telemetry; Laptop A **listens**. That direction matters —
get it backwards and nothing arrives.

---

## One laptop or two?

**Two, for anything beyond quick code iteration.** The deciding fact is that
**only one process can bind UDP 14550** (Windows refuses the second bind).

On one machine, Mission Planner and the backend both want that port, and
whether they actually collide depends on how Mission Planner attaches to SITL
— if it *listens* on 14550 you have to move ports around; if it *forwards*
you're fine. You have to know which, and it differs between versions. On two
machines each has its own 14550 and the question disappears.

The other reasons:

* **SITL is timing-sensitive.** It simulates a flight controller in real time.
  Sharing a laptop with Flutter builds, an Android emulator and Flask produces
  EKF variance warnings, pre-arm failures and stuttering flight that look like
  application bugs but aren't.
* **It demos better** — the drone flying on Mission Planner's map on one
  screen, the app tracking it live on the other.
* **It matches the real deployment**, where the GCS and the analysis server are
  separate machines.

The cost is the firewall rule and keeping the IP in sync, both one-time. Note
that if the Flutter app runs on a **physical phone**, you need the LAN IP and
the TCP 5000 rule anyway — so single-laptop saves you almost nothing.

### When one laptop is the right call

No second machine, no reliable Wi-Fi, fast backend/app iteration where you just
need *a* vehicle responding — or a network with AP/client isolation you cannot
turn off (common on institutional Wi-Fi; test with `ping` first).

Single-laptop config:

```
MAVLINK_URL=udpin:127.0.0.1:14550
```

`BASE_URL=http://127.0.0.1:5000` (desktop/web only). In Mission Planner add the
output as a **UDP client** to `127.0.0.1:14550` so it *sends* rather than
listens. If Mission Planner already holds 14550, give each its own port — MP on
14551, backend on 14550 — rather than fighting over one.

> Replace `192.168.1.3` with your laptop's actual address if it has changed.
> Run `ipconfig` and read the Wi-Fi adapter's **IPv4 Address**. It is handed
> out by DHCP, so it can change when the router restarts.

---

## Part 1 — Laptop A (backend)

### 1.1 Open the firewall

**This is the step people miss.** Your Wi-Fi is on a *Public* network profile,
where Windows blocks all incoming connections by default — the telemetry will
arrive at your network card and be silently discarded.

Open PowerShell **as Administrator** and run:

```powershell
New-NetFirewallRule -DisplayName "AgriVision MAVLink in" -Direction Inbound -Protocol UDP -LocalPort 14550 -Action Allow -Profile Any
```

```powershell
New-NetFirewallRule -DisplayName "AgriVision backend in" -Direction Inbound -Protocol TCP -LocalPort 5000 -Action Allow -Profile Any
```

The second rule is only needed if the Flutter app runs on a phone or on Laptop
B. If everything but the simulator is on Laptop A, you can skip it.

To undo later:

```powershell
Remove-NetFirewallRule -DisplayName "AgriVision MAVLink in","AgriVision backend in"
```

### 1.2 Check the backend config

`backend/my_flask_app/.env` should read:

```
MAVLINK_URL=udpin:0.0.0.0:14550
```

`0.0.0.0` means "listen on every network interface". If it says `127.0.0.1`
the backend only accepts a simulator on the *same* laptop and Laptop B will
never get through.

### 1.3 Start the backend

```bash
cd backend/my_flask_app && python run.py
```

It binds `0.0.0.0:5000`, so it is reachable from the LAN.

### 1.4 Point the app at the right address

`Frontend/agri_vision/assets/.env`:

```
BASE_URL=http://192.168.1.3:5000
```

Use `http://127.0.0.1:5000` only if the app runs on Laptop A itself as
desktop/web. A phone or another laptop needs the LAN IP.

*(This was set to `192.168.31.90` — an address from a different network — and
has been corrected to your current one.)*

---

## Part 2 — Laptop B (Mission Planner)

### 2.1 Start the simulator

1. Open **Mission Planner**.
2. Top toolbar → **SIMULATION**.
3. Choose **Multirotor**, then **Stable** when it offers a firmware channel.
   The first run downloads the SITL binary (a few MB).
4. Wait until the HUD shows a GPS lock and the status reads **Disarmed**
   rather than *No GPS*. Pre-arm checks fail without a 3-D fix, so nothing
   will take off until this settles.

At this point Mission Planner is flying a simulated drone locally. Laptop A
still sees nothing — you have to tell it to send.

### 2.2 Forward the telemetry to Laptop A

In Mission Planner, press **Ctrl+F**. A window of extra tools opens. Click
**Mavlink** — this opens the MAVLink output/forwarding panel. Add a **UDP
Client** output pointing at:

```
192.168.1.3 : 14550
```

> The exact wording differs between Mission Planner versions — the button may
> be labelled *Mavlink*, the panel *MAVLink output* or *Mirror*. You are
> looking for anything that adds a **UDP client / UDP host output** and asks
> for a destination address and port. If your build doesn't have it, use the
> MAVProxy method below, which is version-independent.

**Alternative — MAVProxy (most reliable).** If you have MAVProxy or the
ArduPilot dev environment on Laptop B, skip Mission Planner's UI entirely:

```bash
sim_vehicle.py -v ArduCopter --console --map --out=udp:192.168.1.3:14550
```

`--out` can be repeated, so Mission Planner and AgriVision can both watch the
same simulated aircraft:

```bash
sim_vehicle.py -v ArduCopter --console --map --out=udp:127.0.0.1:14551 --out=udp:192.168.1.3:14550
```

### 2.3 If both Mission Planner and AgriVision are connected at once

Both default to ground-station address **255**. Two stations sharing an
address on one link is a genuine problem: the vehicle addresses its
`MISSION_REQUEST` and `COMMAND_ACK` replies to the requesting id, so the other
station sees them too and can answer first — which corrupts a mission upload
in a way that looks like a random timeout.

On Laptop A, uncomment this line in `backend/my_flask_app/.env` and restart
the backend:

```
MAVLINK_SOURCE_SYSTEM=254
```

Only needed when Mission Planner (or QGroundControl) stays connected. If
Mission Planner is just launching SITL and you drive everything from the app,
leave it alone.

---

## Part 3 — Verify, one hop at a time

Do these in order. Each one isolates a different failure.

### 3.1 Can the laptops see each other?

On Laptop B:

```powershell
ping 192.168.1.3
```

No reply → they are not on the same network, or the router has **AP isolation
/ client isolation** enabled (common on guest networks). Fix that before
anything else; nothing below can work.

### 3.2 Is telemetry actually arriving at Laptop A?

This is the decisive test. On Laptop A:

```bash
cd backend/my_flask_app && python tools/mavlink_listen.py
```

It prints the address Laptop B should be sending to, then waits 20 seconds.

* **HEARTBEAT RECEIVED** → the network path works. Move on.
* **NO HEARTBEAT** → nothing is arriving. It is the firewall (3.1 passed but
  UDP is still blocked), the wrong destination IP on Laptop B, or the
  simulator isn't running. The tool prints this checklist itself.

Add `--watch` to keep printing live position and GPS once connected:

```bash
python tools/mavlink_listen.py --watch
```

> Stop this tool before connecting from the app — two programs cannot listen
> on UDP 14550 at the same time on Windows.

### 3.3 Can the backend open the link?

On Laptop A:

```bash
curl -X POST http://192.168.1.3:5000/api/mavlink/status
```

Actually status is a GET:

```bash
curl http://192.168.1.3:5000/api/mavlink/status
```

Then connect. `/connect` needs a login, so get a token first:

```bash
curl -X POST http://192.168.1.3:5000/api/auth/signin -H "Content-Type: application/json" -d "{\"email\":\"you@example.com\",\"password\":\"yourpassword\"}"
```

```bash
curl -X POST http://192.168.1.3:5000/api/mavlink/connect -H "Content-Type: application/json" -H "Authorization: Bearer PASTE_TOKEN_HERE" -d "{}"
```

A good response contains `"connected": true` and a `telemetry` block with a
`mode` such as `STABILIZE`.

---

## Part 4 — Fly it from the app

1. Sign in (the flight endpoints need a login).
2. Open **Mission Planning**.
3. Tap the **link chip** under the drone status strip, top-left. It reads
   *Connect* while there is no link.
4. Leave the address blank — that uses `MAVLINK_URL` from `.env` — and tap
   **Connect**. The chip turns green and shows the vehicle's flight mode.
5. Build a survey: import a `.kml` boundary or tap waypoints onto the map.
6. Tap **Start Mission** and pick a flight profile.

The waypoints are written to the simulated aircraft, it is switched to AUTO,
armed and launched. Watch the same flight move on Mission Planner's map on
Laptop B at the same time — it is the same drone.

**Return Home** sends RTL, **Emergency Land** sends LAND, and the back arrow
puts it into loiter.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `mavlink_listen.py` says NO HEARTBEAT | Firewall (Part 1.1), wrong destination IP on Laptop B, or simulator not running. |
| Ping fails between laptops | Different networks, or router AP/client isolation. Guest Wi-Fi almost always blocks this. |
| `No heartbeat on … within 15s` from `/connect` | Same as above — but also check `mavlink_listen.py` isn't still running and holding the port. |
| `Address already in use` | Something else holds UDP 14550: the tool, another GCS, or a previous backend that didn't release it. |
| App says "No connection to the server" | `BASE_URL` in `assets/.env` is wrong, TCP 5000 is firewalled, or the backend isn't running. |
| Mission upload times out at random item counts | Two ground stations on id 255 — set `MAVLINK_SOURCE_SYSTEM=254` (Part 2.3). |
| `Vehicle rejected arm` | Pre-arm checks, almost always no GPS lock yet. Wait for a 3-D fix; the reason appears in the link sheet's message list. |
| Worked yesterday, not today | DHCP gave your laptop a new IP. Re-run `ipconfig` and update `BASE_URL` and Laptop B's output address. |

## A note on the IP address

`192.168.1.3` is a DHCP lease — the router can hand you a different one after a
reboot. If this setup is going to be used repeatedly, reserve a static address
for Laptop A in the router's DHCP settings. That single change removes the most
common "it stopped working" cause.
