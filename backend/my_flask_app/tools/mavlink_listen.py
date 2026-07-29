"""Standalone MAVLink listener — proves packets are reaching this machine.

Run this *before* involving the backend or the app. It answers the one
question that every cross-machine setup problem comes down to: is the
simulator's telemetry actually arriving here, or is it being dropped by a
firewall / sent to the wrong address?

    python tools/mavlink_listen.py
    python tools/mavlink_listen.py --url udpin:0.0.0.0:14550 --seconds 20

If it prints a heartbeat, the network path is good and any remaining problem
is in the backend or the app. If it times out, nothing is arriving and the
fix is on the network side — see docs/MAVLINK_REMOTE_SETUP.md.

This does not touch the Flask app or the database, so it is safe to run while
the backend is up — but note that two listeners cannot share UDP port 14550 on
Windows. Stop the backend's link (POST /api/mavlink/disconnect) first, or run
this on a different port.
"""

import argparse
import os
import socket
import sys
import time

# Allow running from the repo root or from tools/.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from pymavlink import mavutil
except ImportError:
    sys.exit(
        "pymavlink is not installed in this environment.\n"
        "  pip install pymavlink"
    )


def local_addresses():
    """Best-effort list of this machine's LAN addresses, for the banner."""
    addresses = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(info[4][0])
    except Exception:
        pass
    try:
        # The address the OS would use to reach the internet — usually the
        # one the other laptop should send to.
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("8.8.8.8", 80))
        addresses.add(probe.getsockname()[0])
        probe.close()
    except Exception:
        pass
    return sorted(a for a in addresses if not a.startswith("127."))


def main():
    parser = argparse.ArgumentParser(
        description="Listen for MAVLink and report what arrives."
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("MAVLINK_URL", "udpin:0.0.0.0:14550"),
        help="pymavlink connection string (default: %(default)s)",
    )
    parser.add_argument(
        "--seconds", type=float, default=20.0,
        help="how long to wait for a heartbeat (default: %(default)s)",
    )
    parser.add_argument(
        "--watch", action="store_true",
        help="after the first heartbeat, keep printing live telemetry",
    )
    args = parser.parse_args()

    print(f"Listening on {args.url}")
    for address in local_addresses():
        port = args.url.rsplit(":", 1)[-1]
        print(f"  the other machine should send to:  {address}:{port}")
    print(f"Waiting up to {args.seconds:.0f}s for a heartbeat…\n")

    try:
        master = mavutil.mavlink_connection(args.url, source_system=254)
    except Exception as exc:
        sys.exit(
            f"Could not open {args.url}: {exc}\n"
            "If this says 'address already in use', something else already "
            "holds that port — the backend's own link, or another GCS."
        )

    heartbeat = master.wait_heartbeat(timeout=args.seconds)
    if heartbeat is None:
        print("NO HEARTBEAT.\n")
        print("Nothing reached this machine. Work through these in order:")
        print("  1. Is the simulator actually running on the other laptop?")
        print("  2. Is it sending to THIS machine's IP (see above), not to")
        print("     127.0.0.1 or an old address?")
        print("  3. Windows Firewall: inbound UDP on this port must be")
        print("     allowed — on a 'Public' network it is blocked by default.")
        print("  4. Can the two machines see each other at all?  ping them.")
        print("  5. Some Wi-Fi routers have 'AP isolation' / 'client")
        print("     isolation' on, which blocks laptop-to-laptop traffic.")
        return 1

    print("HEARTBEAT RECEIVED")
    print(f"  from system {heartbeat.get_srcSystem()} "
          f"component {heartbeat.get_srcComponent()}")
    print(f"  vehicle type   {mavutil.mavlink.enums['MAV_TYPE'][heartbeat.type].name}")
    print(f"  autopilot      "
          f"{mavutil.mavlink.enums['MAV_AUTOPILOT'][heartbeat.autopilot].name}")
    print(f"  flight mode    {master.flightmode}")
    armed = bool(
        heartbeat.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED
    )
    print(f"  armed          {armed}")
    print("\nThe network path works. Point the backend at this same URL.")

    if not args.watch:
        return 0

    print("\nLive telemetry (Ctrl+C to stop):")
    deadline = time.time() + 3600
    while time.time() < deadline:
        msg = master.recv_match(
            type=["GLOBAL_POSITION_INT", "VFR_HUD", "GPS_RAW_INT", "STATUSTEXT"],
            blocking=True,
            timeout=2,
        )
        if msg is None:
            continue
        kind = msg.get_type()
        if kind == "GLOBAL_POSITION_INT":
            print(f"  pos  {msg.lat / 1e7:.6f}, {msg.lon / 1e7:.6f}  "
                  f"alt {msg.relative_alt / 1000.0:.1f} m")
        elif kind == "VFR_HUD":
            print(f"  hud  {msg.groundspeed:.1f} m/s  hdg {msg.heading}°  "
                  f"alt {msg.alt:.1f} m")
        elif kind == "GPS_RAW_INT":
            print(f"  gps  fix {msg.fix_type}  "
                  f"{msg.satellites_visible} sats")
        elif kind == "STATUSTEXT":
            text = msg.text
            if isinstance(text, bytes):
                text = text.decode("utf-8", errors="replace")
            print(f"  msg  {text.strip()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
