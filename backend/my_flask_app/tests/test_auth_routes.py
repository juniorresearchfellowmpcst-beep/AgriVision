import pytest
from app import create_app
from app.core.database import db


@pytest.fixture()
def client():
    app = create_app({
        "TESTING": True,
        # Isolated from the developer's real database. This MUST go through
        # create_app: overriding the config afterwards leaves the engine bound
        # to the dev database, and drop_all() then deletes real data.
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
        "JWT_SECRET_KEY": "test-secret",
    })

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


# ── Forgot / reset password (OTP) ────────────────────────────────────────────

def _signup(client, email, password='secret123'):
    return client.post(
        '/api/auth/signup',
        json={'name': 'Reset User', 'email': email, 'password': password},
    )


def test_forgot_and_reset_password_flow(client, monkeypatch):
    # No SMTP configured in tests, so the OTP comes back as debug_otp.
    monkeypatch.delenv('MAIL_SERVER', raising=False)
    _signup(client, 'reset@example.com', 'oldpass123')

    forgot = client.post('/api/auth/forgot-password', json={'email': 'reset@example.com'})
    assert forgot.status_code == 200
    otp = forgot.get_json().get('debug_otp')
    assert otp and len(otp) == 6

    reset = client.post('/api/auth/reset-password', json={
        'email': 'reset@example.com', 'otp': otp, 'password': 'newpass456',
    })
    assert reset.status_code == 200

    # Old password no longer works; new one does.
    assert client.post('/api/auth/signin', json={
        'email': 'reset@example.com', 'password': 'oldpass123'}).status_code == 401
    assert client.post('/api/auth/signin', json={
        'email': 'reset@example.com', 'password': 'newpass456'}).status_code == 200


def test_forgot_password_unknown_email_is_generic(client, monkeypatch):
    monkeypatch.delenv('MAIL_SERVER', raising=False)
    resp = client.post('/api/auth/forgot-password', json={'email': 'nobody@example.com'})
    assert resp.status_code == 200
    # No account -> no debug_otp leaked, but still a generic success.
    assert 'debug_otp' not in resp.get_json()


def test_reset_password_wrong_otp_returns_400(client, monkeypatch):
    monkeypatch.delenv('MAIL_SERVER', raising=False)
    _signup(client, 'wrongotp@example.com')
    client.post('/api/auth/forgot-password', json={'email': 'wrongotp@example.com'})

    resp = client.post('/api/auth/reset-password', json={
        'email': 'wrongotp@example.com', 'otp': '000000', 'password': 'newpass456',
    })
    assert resp.status_code == 400


def test_a_code_is_burned_after_five_wrong_guesses(client, monkeypatch):
    """A six-digit code is a million possibilities; guessing must not be free.

    The route limiter counts per caller address, so several addresses simply
    share the work out between them. The budget therefore belongs to the code.
    """
    monkeypatch.delenv('MAIL_SERVER', raising=False)
    # The route's own rate limit would mask this, and it is not what is under
    # test here.
    client.application.config['RATELIMIT_ENABLED'] = False

    _signup(client, 'brute@example.com')
    otp = client.post(
        '/api/auth/forgot-password', json={'email': 'brute@example.com'}
    ).get_json()['debug_otp']

    wrong = '000000' if otp != '000000' else '111111'
    for _ in range(5):
        assert client.post('/api/auth/reset-password', json={
            'email': 'brute@example.com', 'otp': wrong, 'password': 'newpass456',
        }).status_code == 400

    # The budget is spent, so even the *right* code no longer works. The
    # account owner asks for a fresh one; the guesser starts over at zero.
    spent = client.post('/api/auth/reset-password', json={
        'email': 'brute@example.com', 'otp': otp, 'password': 'newpass456',
    })
    assert spent.status_code == 400
    assert client.post('/api/auth/signin', json={
        'email': 'brute@example.com', 'password': 'newpass456'}).status_code == 401


def test_a_mistyped_digit_does_not_burn_the_code(client, monkeypatch):
    """Five is a budget for fat fingers, not a hair trigger."""
    monkeypatch.delenv('MAIL_SERVER', raising=False)
    client.application.config['RATELIMIT_ENABLED'] = False

    _signup(client, 'typo@example.com')
    otp = client.post(
        '/api/auth/forgot-password', json={'email': 'typo@example.com'}
    ).get_json()['debug_otp']

    wrong = '000000' if otp != '000000' else '111111'
    for _ in range(4):
        client.post('/api/auth/reset-password', json={
            'email': 'typo@example.com', 'otp': wrong, 'password': 'newpass456',
        })

    assert client.post('/api/auth/reset-password', json={
        'email': 'typo@example.com', 'otp': otp, 'password': 'newpass456',
    }).status_code == 200


def test_asking_again_clears_the_guess_budget(client, monkeypatch):
    """A locked-out owner must have a way back in: request a new code."""
    monkeypatch.delenv('MAIL_SERVER', raising=False)
    client.application.config['RATELIMIT_ENABLED'] = False

    _signup(client, 'again@example.com')
    client.post('/api/auth/forgot-password', json={'email': 'again@example.com'})
    for _ in range(5):
        client.post('/api/auth/reset-password', json={
            'email': 'again@example.com', 'otp': '000000', 'password': 'newpass456',
        })

    fresh = client.post(
        '/api/auth/forgot-password', json={'email': 'again@example.com'}
    ).get_json()['debug_otp']
    assert client.post('/api/auth/reset-password', json={
        'email': 'again@example.com', 'otp': fresh, 'password': 'newpass456',
    }).status_code == 200


def test_a_wrong_guess_is_not_told_apart_from_an_expired_code(client, monkeypatch):
    """One message for every failure, so nothing confirms a code exists."""
    monkeypatch.delenv('MAIL_SERVER', raising=False)
    client.application.config['RATELIMIT_ENABLED'] = False

    _signup(client, 'quiet@example.com')
    client.post('/api/auth/forgot-password', json={'email': 'quiet@example.com'})

    guessed = client.post('/api/auth/reset-password', json={
        'email': 'quiet@example.com', 'otp': '000000', 'password': 'newpass456',
    }).get_json()['message']
    never_asked = client.post('/api/auth/reset-password', json={
        'email': 'stranger@example.com', 'otp': '000000', 'password': 'newpass456',
    }).get_json()['message']

    assert guessed == never_asked


def test_health_says_whether_reset_codes_can_be_emailed(client, monkeypatch):
    """The one failure the reset endpoint cannot report on its own.

    With no SMTP the reset call still answers 200 and the same generic
    sentence, because saying otherwise would reveal which addresses are
    registered. So an undelivered code is indistinguishable from a delivered
    one, and the operator needs somewhere else to look.
    """
    monkeypatch.delenv('MAIL_SERVER', raising=False)
    email = client.get('/api/system/health').get_json()['modules']['email']
    assert email['configured'] is False
    assert 'MAIL_SERVER' in email['detail']

    monkeypatch.setenv('MAIL_SERVER', 'smtp.gmail.com')
    monkeypatch.setenv('MAIL_USERNAME', 'bot@example.com')
    monkeypatch.setenv('MAIL_PASSWORD', 'app-password')
    email = client.get('/api/system/health').get_json()['modules']['email']
    assert email['configured'] is True
    # Configuration, never credentials.
    assert 'app-password' not in str(email)


# ── Google sign-in ───────────────────────────────────────────────────────────

class _FakeResp:
    def __init__(self, status_code, payload):
        self.status_code = status_code
        self._payload = payload

    def json(self):
        return self._payload


def test_google_signin_creates_user_and_returns_token(client, monkeypatch):
    monkeypatch.delenv('GOOGLE_CLIENT_ID', raising=False)

    def fake_get(url, params=None, timeout=None):
        return _FakeResp(200, {
            'aud': 'any-client-id',
            'email': 'guser@gmail.com',
            'email_verified': 'true',
            'name': 'Google User',
        })

    monkeypatch.setattr('app.services.auth_service.requests.get', fake_get)

    resp = client.post('/api/auth/google', json={'id_token': 'fake-token'})
    assert resp.status_code == 200
    body = resp.get_json()
    assert 'access_token' in body
    assert body['user']['email'] == 'guser@gmail.com'


def test_google_signin_audience_mismatch_returns_401(client, monkeypatch):
    monkeypatch.setenv('GOOGLE_CLIENT_ID', 'expected-client-id')

    def fake_get(url, params=None, timeout=None):
        return _FakeResp(200, {
            'aud': 'some-other-client-id',
            'email': 'x@gmail.com',
            'email_verified': 'true',
        })

    monkeypatch.setattr('app.services.auth_service.requests.get', fake_get)

    resp = client.post('/api/auth/google', json={'id_token': 'fake-token'})
    assert resp.status_code == 401
