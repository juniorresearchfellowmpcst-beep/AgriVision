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


def test_signup_and_signin(client):
    signup_response = client.post(
        '/api/auth/signup',
        json={'name': 'Test User', 'email': 'test@example.com', 'password': 'secret123'},
    )
    assert signup_response.status_code == 201

    signin_response = client.post(
        '/api/auth/signin',
        json={'email': 'test@example.com', 'password': 'secret123'},
    )
    assert signin_response.status_code == 200
    assert 'access_token' in signin_response.get_json()


def test_signup_duplicate_email_returns_409(client):
    payload = {'name': 'Test User', 'email': 'dupe@example.com', 'password': 'secret123'}
    client.post('/api/auth/signup', json=payload)
    response = client.post('/api/auth/signup', json=payload)
    assert response.status_code == 409


def test_signin_wrong_password_returns_401(client):
    client.post(
        '/api/auth/signup',
        json={'name': 'Test User', 'email': 'wrongpw@example.com', 'password': 'secret123'},
    )
    response = client.post(
        '/api/auth/signin',
        json={'email': 'wrongpw@example.com', 'password': 'not-the-password'},
    )
    assert response.status_code == 401


def test_signup_missing_field_returns_400(client):
    response = client.post(
        '/api/auth/signup',
        json={'name': 'Test User', 'email': 'missing@example.com'},
    )
    assert response.status_code == 400


def test_signin_missing_field_returns_400(client):
    response = client.post('/api/auth/signin', json={'email': 'a@b.com'})
    assert response.status_code == 400
