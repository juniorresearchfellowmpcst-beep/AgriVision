"""Tests for the connection-info and aggregate-health endpoints.

The settings screen reads these to tell an operator where to point Mission
Planner. Two things must hold or that advice is worse than none:

  * the direction must be right — the backend listens, the ground station
    sends — and a dial-out configuration must not be presented as something a
    GCS can connect to;
  * a broken subsystem must not take the whole report down, because the report
    is how you find out which subsystem is broken.
"""

import pytest

from app import create_app
from app.services.system_service import (
    SystemService,
    local_ipv4_addresses,
    parse_endpoint,
)


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as test_client:
        yield test_client


# ── endpoint parsing ──────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "url, expected",
    [
        ("udpin:0.0.0.0:14550", ("udpin", "0.0.0.0", 14550)),
        ("udpout:10.0.0.5:14550", ("udpout", "10.0.0.5", 14550)),
        ("tcp:127.0.0.1:5762", ("tcp", "127.0.0.1", 5762)),
        ("COM5", ("serial", "COM5", None)),
        ("/dev/ttyUSB0", ("serial", "/dev/ttyUSB0", None)),
        ("", ("unknown", None, None)),
        ("nonsense", ("unknown", None, None)),
    ],
)
def test_connection_strings_are_parsed(url, expected):
    assert parse_endpoint(url) == expected


def test_a_malformed_endpoint_does_not_raise():
    """This feeds a settings screen; it must degrade, never explode."""
    for bad in (None, "udpin:", ":::", "udpin:host:notaport"):
        scheme, _host, _port = parse_endpoint(bad)
        assert scheme in ("unknown", "serial")


# ── links ─────────────────────────────────────────────────────────────────

def test_links_reports_an_api_url_and_a_hostname(client):
    body = client.get("/api/system/links").get_json()
    assert body["status"] == "ok"
    assert body["hostname"]
    assert body["api"]["base_url"].startswith("http")


def test_listening_endpoint_gives_a_gcs_target(client, monkeypatch):
    """udpin means a ground station can send here, so name the address."""
    monkeypatch.setenv("MAVLINK_URL", "udpin:0.0.0.0:14550")
    body, _status = SystemService.links(api_port=5000)

    assert body["mavlink"]["listening"] is True
    if body["addresses"]:                       # no LAN on a sandboxed CI box
        target = body["mavlink"]["gcs_targets"][0]
        assert target["transport"] == "UDP"
        assert target["port"] == 14550
        assert target["address"].endswith(":14550")


def test_dial_out_endpoint_offers_no_gcs_target(monkeypatch):
    """A tcp: endpoint dials the vehicle; nothing can connect inbound.

    Presenting an address here would send an operator to a port that is not
    listening, which is the single most confusing failure in this feature.
    """
    monkeypatch.setenv("MAVLINK_URL", "tcp:127.0.0.1:5762")
    body, _status = SystemService.links(api_port=5000)

    assert body["mavlink"]["listening"] is False
    assert body["mavlink"]["gcs_targets"] == []
    assert any("dials out" in h for h in body["hints"])


def test_listen_targets_are_offered_even_when_dialling_out(monkeypatch):
    """The operator still needs the address they would switch to."""
    monkeypatch.setenv("MAVLINK_URL", "tcp:127.0.0.1:5762")
    body, _status = SystemService.links(api_port=5000)

    assert body["mavlink"]["listen_url"] == "udpin:0.0.0.0:14550"
    for target in body["mavlink"]["listen_targets"]:
        assert target["port"] == 14550


def test_serial_link_says_no_network_connection_is_possible(monkeypatch):
    monkeypatch.setenv("MAVLINK_URL", "COM5")
    body, _status = SystemService.links(api_port=5000)

    assert body["mavlink"]["scheme"] == "serial"
    assert body["mavlink"]["gcs_targets"] == []
    assert any("serial radio" in h for h in body["hints"])


def test_the_14550_conflict_is_called_out(monkeypatch):
    """Only one process per machine can hold 14550 — say so before it bites."""
    monkeypatch.setenv("MAVLINK_URL", "udpin:0.0.0.0:14550")
    body, _status = SystemService.links(api_port=5000)
    assert any("14550" in h and "one program" in h for h in body["hints"])


def test_loopback_is_never_offered_as_an_address():
    """127.0.0.1 is useless to the other machine and must not be suggested."""
    for address in local_ipv4_addresses():
        assert not address.startswith(("127.", "169.254.", "0."))


# ── health ────────────────────────────────────────────────────────────────

def test_health_reports_every_module(client):
    body = client.get("/api/system/health").get_json()
    assert body["status"] in ("ok", "degraded")
    for name in ("database", "disease", "field_scan", "mavlink", "cameras"):
        assert name in body["modules"], f"{name} missing from health report"
        assert "state" in body["modules"][name]


def test_health_survives_a_broken_module(client, monkeypatch):
    """One failing subsystem must not take the report down with it."""
    import app.services.system_service as module

    def explode():
        raise RuntimeError("simulated failure")

    original = module.link.snapshot
    monkeypatch.setattr(module.link, "snapshot", explode)
    try:
        body = client.get("/api/system/health").get_json()
    finally:
        monkeypatch.setattr(module.link, "snapshot", original)

    assert body["status"] == "degraded"
    assert "mavlink" in body["degraded"]
    assert body["modules"]["mavlink"]["state"] == "error"
    # The healthy modules still reported.
    assert body["modules"]["database"]["state"] == "ok"
