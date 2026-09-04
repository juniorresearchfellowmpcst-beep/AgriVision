"""What this backend is reachable at, so other software can be pointed at it.

Two audiences, one problem each:

  * **The app** needs the API base URL. Usually it already has one, but when
    the backend moves to another laptop or the Wi-Fi hands out a new lease, the
    operator has to discover the new address from somewhere.
  * **Ground-control software** — Mission Planner, QGroundControl, MAVProxy —
    needs to *push* telemetry here. That means a host and a UDP port, and the
    single most common field failure is getting the direction backwards: the
    backend listens (``udpin``), the GCS sends. This module produces the exact
    string to type into the other program, rather than leaving the operator to
    derive it from an interface list.

Nothing here is sensitive. It reports private LAN addresses and the ports this
process already listens on — the same information anyone on the network can
discover with a port scan, and useless to anyone who is not on it.
"""

from __future__ import annotations

import os
import re
import socket
from typing import Any, Dict, List, Optional, Tuple

# `link` is the process-wide instance; DEFAULT_URL is a module constant, so
# both come from the module rather than the package re-export.
from app.mavlink.link import DEFAULT_URL, link

# Addresses that are never worth showing an operator: loopback (the other
# machine cannot reach it), link-local autoconfiguration (means DHCP failed),
# and the unspecified address.
_USELESS_PREFIXES = ("127.", "169.254.", "0.")

# The port a ground station sends to when this backend is set to listen.
# 14550 is the MAVLink convention and what Mission Planner / QGC default to.
DEFAULT_LISTEN_PORT = 14550


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def _primary_lan_ip() -> Optional[str]:
    """The address this host would use to reach the rest of the network.

    Opens a UDP socket toward a public address and reads back the local end.
    No packets are sent — UDP ``connect`` only fixes the route — so this works
    with no internet, provided a default route exists.
    """
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.settimeout(0.4)
        probe.connect(("8.8.8.8", 80))
        return probe.getsockname()[0]
    except Exception:
        return None
    finally:
        probe.close()


def local_ipv4_addresses() -> List[str]:
    """Every LAN IPv4 address worth telling somebody about, best guess first.

    A machine on both Wi-Fi and a drone's own access point has two, and which
    one the operator needs depends on where the other software is running — so
    all of them are reported rather than one being picked.
    """
    found: List[str] = []

    primary = _primary_lan_ip()
    if primary and not primary.startswith(_USELESS_PREFIXES):
        found.append(primary)

    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = info[4][0]
            if address.startswith(_USELESS_PREFIXES) or address in found:
                continue
            found.append(address)
    except Exception:
        pass  # an unresolvable hostname is common and not worth failing over

    return found


def parse_endpoint(url: str) -> Tuple[str, Optional[str], Optional[int]]:
    """Split a pymavlink connection string into (scheme, host, port).

    Returns ``("serial", "COM5", None)`` for a radio, since a serial port has
    neither. An unparseable string yields ``("unknown", None, None)`` rather
    than raising — this is display code and must not break the settings screen.
    """
    text = str(url or "").strip()
    if not text:
        return ("unknown", None, None)

    match = re.match(r"^(udpin|udpout|udp|tcpin|tcp|tcpout):(.+?):(\d+)$", text)
    if match:
        return (match.group(1), match.group(2), int(match.group(3)))

    # COM5, /dev/ttyUSB0, /dev/ttyACM0 — a serial radio.
    if text.upper().startswith("COM") or text.startswith("/dev/"):
        return ("serial", text, None)

    return ("unknown", None, None)


def _listens_for_incoming(scheme: str) -> bool:
    """Does this endpoint wait to be connected to, rather than dialling out?"""
    return scheme in ("udpin", "udp", "tcpin")


class SystemService:
    """Connection information for the app and for external ground stations."""

    @staticmethod
    def links(api_port: int = 5000, api_scheme: str = "http") -> Tuple[Dict[str, Any], int]:
        """Everything needed to point another program at this backend."""
        addresses = local_ipv4_addresses()
        hostname = socket.gethostname()

        api_urls = [f"{api_scheme}://{ip}:{api_port}" for ip in addresses]

        configured = os.environ.get("MAVLINK_URL", DEFAULT_URL)
        scheme, host, port = parse_endpoint(configured)

        # What to type into Mission Planner / QGroundControl. Only meaningful
        # when we are the listening side; if the backend dials out to the
        # vehicle there is nothing for a GCS to connect *to* here.
        gcs_targets: List[Dict[str, Any]] = []
        if _listens_for_incoming(scheme) and port:
            transport = "UDP" if scheme.startswith("udp") else "TCP"
            for ip in addresses:
                gcs_targets.append({
                    "transport": transport,
                    "host": ip,
                    "port": port,
                    "address": f"{ip}:{port}",
                    # MAVProxy / mavlink-router take a full string.
                    "mavproxy": f"--out=udp:{ip}:{port}" if transport == "UDP"
                                else f"--out=tcp:{ip}:{port}",
                })

        snapshot = link.snapshot()

        # When a link is already open, report the URL it is actually using
        # rather than the configured default — they differ the moment an
        # operator connects to something else from the app, and showing the
        # stale one would send a ground station to the wrong port.
        active_url = snapshot.get("url") or configured
        if active_url != configured:
            scheme, host, port = parse_endpoint(active_url)
            gcs_targets = []
            if _listens_for_incoming(scheme) and port:
                transport = "UDP" if scheme.startswith("udp") else "TCP"
                for ip in addresses:
                    gcs_targets.append({
                        "transport": transport,
                        "host": ip,
                        "port": port,
                        "address": f"{ip}:{port}",
                        "mavproxy": f"--out={transport.lower()}:{ip}:{port}",
                    })

        # Even when the backend is currently dialling *out* to the vehicle, an
        # operator setting up a ground station needs to see the address they
        # would use if they switched to listening mode. Telling them only
        # "change MAVLINK_URL" leaves them to work the address out themselves,
        # which is the step that goes wrong.
        listen_port = port if _listens_for_incoming(scheme) and port else DEFAULT_LISTEN_PORT
        listen_targets = [
            {
                "transport": "UDP",
                "host": ip,
                "port": listen_port,
                "address": f"{ip}:{listen_port}",
                "mavproxy": f"--out=udp:{ip}:{listen_port}",
            }
            for ip in addresses
        ]

        return {
            "status": "ok",
            "hostname": hostname,
            "api": {
                "port": api_port,
                "urls": api_urls,
                # The value to paste into the app's assets/.env BASE_URL.
                "base_url": api_urls[0] if api_urls else f"{api_scheme}://127.0.0.1:{api_port}",
            },
            "mavlink": {
                "configured_url": configured,
                "active_url": snapshot.get("url"),
                "scheme": scheme,
                "host": host,
                "port": port,
                "listening": _listens_for_incoming(scheme),
                "available": bool(snapshot.get("available")),
                "connected": bool(snapshot.get("connected")),
                "alive": bool(snapshot.get("alive")),
                "source_system": _env_int("MAVLINK_SOURCE_SYSTEM", 255),
                "gcs_targets": gcs_targets,
                # Where a ground station would send if this backend were
                # listening. Identical to gcs_targets when it already is.
                "listen_targets": listen_targets,
                "listen_url": f"udpin:0.0.0.0:{listen_port}",
            },
            "addresses": addresses,
            "hints": SystemService._hints(scheme, port, addresses),
        }, 200

    @staticmethod
    def health() -> Tuple[Dict[str, Any], int]:
        """Roll every module's readiness into one answer.

        Each check is wrapped: a module that raises reports ``error`` and the
        rest of the report still comes back. A health endpoint that itself
        500s when one subsystem is unhappy is worse than useless, because it
        cannot tell you *which* subsystem.
        """
        modules: Dict[str, Any] = {}

        def probe(name: str, fn) -> None:
            try:
                modules[name] = fn()
            except Exception as exc:  # pragma: no cover - defensive
                modules[name] = {"state": "error", "detail": str(exc)}

        def disease() -> Dict[str, Any]:
            from app.ai import model_loader
            info = model_loader.info()
            return {
                "state": "ok",
                "engine": info["engine"],
                "model": info["model_file"],
                "classes": info["classes"],
            }

        def field_scan() -> Dict[str, Any]:
            from app.ai.crop_model import disease_model, weed_model
            return {
                "state": "ok",
                "disease_engine": "model" if disease_model.is_available() else "heuristic",
                "weed_engine": "model" if weed_model.is_available() else "heuristic",
            }

        def mavlink_state() -> Dict[str, Any]:
            snapshot = link.snapshot()
            return {
                "state": "ok" if snapshot.get("available") else "unavailable",
                "available": bool(snapshot.get("available")),
                "connected": bool(snapshot.get("connected")),
                "alive": bool(snapshot.get("alive")),
                "url": snapshot.get("url"),
                "detail": None if snapshot.get("available")
                          else "pymavlink is not installed on the server.",
            }

        def database() -> Dict[str, Any]:
            from sqlalchemy import text

            from app.core.database import db
            db.session.execute(text("SELECT 1"))
            return {"state": "ok"}

        def cameras() -> Dict[str, Any]:
            from app.api.models.capture import CameraFeed
            rows = CameraFeed.query.all()
            enabled = [c for c in rows if c.enabled]
            return {
                "state": "ok",
                "registered": len(rows),
                "enabled": len(enabled),
                "multispectral": sum(1 for c in enabled if c.role == "multispectral"),
                "rgb": sum(1 for c in enabled if c.role == "rgb"),
            }

        def email() -> Dict[str, Any]:
            """Whether password-reset codes can actually be delivered.

            Worth reporting because its failure is silent by design: when SMTP
            is unset the reset endpoint still answers 200 with the same
            "if an account exists, a code has been sent" as always -- it has to,
            or the response would say which addresses are registered. So from
            the outside a completely undelivered code looks exactly like a
            delivered one, and the only way to tell is to ask the server
            whether it has a mail server at all.

            Reports configuration, never credentials.
            """
            from app.core.mailer import mail_configured

            configured = mail_configured()
            return {
                "state": "ok" if configured else "unconfigured",
                "configured": configured,
                "server": os.environ.get("MAIL_SERVER") if configured else None,
                "detail": None if configured else (
                    "No SMTP server is configured, so password-reset codes are "
                    "not emailed. Set MAIL_SERVER, MAIL_USERNAME and "
                    "MAIL_PASSWORD. Until then the reset code is returned in "
                    "the API response as debug_otp, which is a development "
                    "convenience and must not be relied on in production."
                ),
            }

        probe("database", database)
        probe("disease", disease)
        probe("field_scan", field_scan)
        probe("mavlink", mavlink_state)
        probe("cameras", cameras)
        probe("email", email)

        degraded = [k for k, v in modules.items() if v.get("state") == "error"]
        return {
            "status": "ok" if not degraded else "degraded",
            "degraded": degraded,
            "modules": modules,
        }, 200

    @staticmethod
    def _hints(scheme: str, port: Optional[int], addresses: List[str]) -> List[str]:
        """Plain instructions for the case the operator is actually in."""
        hints: List[str] = []

        if not addresses:
            hints.append(
                "This machine has no usable LAN address. Connect it to the same "
                "Wi-Fi as the drone or the ground station before pairing."
            )
            return hints

        first = addresses[0]

        if _listens_for_incoming(scheme) and port:
            hints.append(
                f"In Mission Planner or QGroundControl, send telemetry to "
                f"UDP {first}:{port}. This backend listens; the ground station "
                f"sends."
            )
            if port == 14550:
                hints.append(
                    "Port 14550 can only be held by one program per machine. "
                    "If Mission Planner is running on THIS computer it already "
                    "has it — run the simulator on a second machine, or point "
                    "this backend at a TCP port such as tcp:127.0.0.1:5762."
                )
        elif scheme == "serial":
            hints.append(
                "The link is set to a serial radio, so no ground station can "
                "connect over the network. Switch to a udpin: endpoint to "
                "accept telemetry from Mission Planner."
            )
        else:
            hints.append(
                "This backend dials out to the vehicle, so there is no inbound "
                "port for a ground station. Set MAVLINK_URL to "
                "udpin:0.0.0.0:14550 to accept an incoming stream instead."
            )

        if len(addresses) > 1:
            hints.append(
                "This machine has more than one network address. Use the one on "
                "the same network as the other program."
            )
        return hints
