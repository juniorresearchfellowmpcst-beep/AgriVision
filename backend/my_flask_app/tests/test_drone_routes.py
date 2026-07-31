"""Drone status / pairing behaviour.

The point of these: with no aircraft connected the API must say so rather
than hand the app numbers to render.
"""

import pytest
from app import create_app
from app.core.database import db


@pytest.fixture()
def client():
    app = create_app()
    app.config.update(
        TESTING=True,
        SQLALCHEMY_DATABASE_URI='sqlite:///:memory:',
        JWT_SECRET_KEY='test-secret',
    )

    with app.app_context():
        db.drop_all()
        db.create_all()

    with app.test_client() as client:
        yield client

    with app.app_context():
        db.session.remove()
        db.drop_all()


def auth_headers(client, email='pilot@example.com'):
    client.post(
        '/api/auth/signup',
        json={'name': 'Pilot', 'email': email, 'password': 'secret123'},
    )
    token = client.post(
        '/api/auth/signin', json={'email': email, 'password': 'secret123'}
    ).get_json()['access_token']
    return {'Authorization': f'Bearer {token}'}


def test_status_without_pairing_returns_no_drone(client):
    """A fresh install has no hardware: no demo unit is conjured up."""
    response = client.get('/api/drones/status')

    assert response.status_code == 200
    body = response.get_json()
    assert body['status'] == 'ok'
    assert body['drone'] is None


def test_status_signed_in_without_pairing_returns_no_drone(client):
    headers = auth_headers(client)

    body = client.get('/api/drones/status', headers=headers).get_json()

    assert body['drone'] is None


def test_pairing_registers_an_unknown_serial(client):
    headers = auth_headers(client)

    response = client.post(
        '/api/drones/pair',
        json={'serial_number': 'ADU-TEST-0001', 'name': 'Field Unit 1'},
        headers=headers,
    )

    assert response.status_code == 200
    body = response.get_json()
    drone = body['drone']
    assert drone['serial_number'] == 'ADU-TEST-0001'
    assert drone['name'] == 'Field Unit 1'
    # Creating an aircraft and pairing with a known one must not look the same
    # to the operator — a typo'd serial silently registering a second unit is
    # otherwise indistinguishable from success.
    assert body['registered'] is True
    assert 'registered' in body['message'].lower()


def test_pairing_a_known_serial_says_it_matched_rather_than_registered(client):
    headers = auth_headers(client)
    client.post(
        '/api/drones/pair',
        json={'serial_number': 'ADU-TEST-0002', 'name': 'Field Unit 2'},
        headers=headers,
    )

    # Re-pair the same aircraft: it already exists, so nothing is registered.
    response = client.post(
        '/api/drones/pair',
        json={'serial_number': 'ADU-TEST-0002'},
        headers=headers,
    )

    assert response.status_code == 200
    body = response.get_json()
    assert body['registered'] is False
    assert 'registered' not in body['message'].lower()
    assert 'ADU-TEST-0002' in body['message']
    # The original name survives a bare re-pair.
    assert body['drone']['name'] == 'Field Unit 2'


def test_paired_drone_reports_no_gauges_until_telemetry_arrives(client):
    """Paired is not connected: the gauges stay unknown, not zero."""
    headers = auth_headers(client)
    client.post(
        '/api/drones/pair',
        json={'serial_number': 'ADU-TEST-0002'},
        headers=headers,
    )

    drone = client.get('/api/drones/status', headers=headers).get_json()['drone']

    assert drone['is_connected'] is False
    assert drone['battery_percent'] is None
    assert drone['tank_percent'] is None
    assert drone['gps_satellites'] is None
    assert drone['telemetry_fresh'] is False


def test_pushed_telemetry_is_reported_then_ages_out(client):
    from datetime import datetime, timedelta

    from app.repositories.drone_repository import DroneRepository
    from app.services.drone_service import TELEMETRY_TTL_S

    headers = auth_headers(client)
    drone_id = client.post(
        '/api/drones/pair',
        json={'serial_number': 'ADU-TEST-0003'},
        headers=headers,
    ).get_json()['drone']['id']

    client.put(
        f'/api/drones/{drone_id}/telemetry',
        json={'battery_percent': 71, 'tank_percent': 40, 'is_connected': True},
    )

    fresh = client.get('/api/drones/status', headers=headers).get_json()['drone']
    assert fresh['battery_percent'] == 71
    assert fresh['is_connected'] is True

    # Wind the clock past the TTL: the same row must stop reporting gauges.
    stale_drone = DroneRepository.get_by_id(drone_id)
    stale_drone.last_seen = datetime.utcnow() - timedelta(
        seconds=TELEMETRY_TTL_S + 60
    )
    DroneRepository.save()

    stale = client.get('/api/drones/status', headers=headers).get_json()['drone']
    assert stale['battery_percent'] is None
    assert stale['is_connected'] is False


def test_unpair_leaves_the_account_with_no_drone(client):
    headers = auth_headers(client)
    client.post(
        '/api/drones/pair',
        json={'serial_number': 'ADU-TEST-0004'},
        headers=headers,
    )

    assert client.post('/api/drones/unpair', headers=headers).status_code == 200
    assert client.get(
        '/api/drones/status', headers=headers
    ).get_json()['drone'] is None
