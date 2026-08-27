# Deploying AgriVision

## Where this runs

**On a ground station on the drone's network** — a laptop or edge box at the
field. This is not really a choice: `app/mavlink/link.py` runs its reader
thread *inside* the Flask process, and `app/capture/live.py` opens the cameras
from there too. A cloud-only backend cannot fly a mission or see a camera.

A cloud deployment (Railway et al.) is still useful for accounts, history and
reports — it just is not where flight or video happens.

```
  ┌──────────────── field network ─────────────────┐
  │  drone cameras ──┐                             │
  │  flight ctrl ────┼──► Flask (ground station)   │ ◄── handsets
  └──────────────────┴────────────┬────────────────┘
                                  │ optional
                                  ▼
                        Postgres / cloud mirror
```

---

## Starting it

**Development** — no configuration needed at all:

```bash
python run.py
```

**Production:**

```bash
gunicorn --chdir backend/my_flask_app -c gunicorn.conf.py run:app
```

`run.py`'s `app.run()` is a development server. It is now `threaded=True` so a
live viewer does not block the whole app, but it is still single-process and
unsupervised — use gunicorn for anything real. The root `Procfile` already
does.

---

## Configuration

Everything is an environment variable. The defaults are chosen so a developer
needs none of them.

### Refuses to start without these in production

Set `APP_ENV=production` and the app checks itself at boot, reporting **every**
problem at once rather than one per restart:

| Variable | Why it must be set |
| --- | --- |
| `SECRET_KEY` | The default is in this repository. |
| `JWT_SECRET_KEY` | The default is in this repository — anyone who has read it could sign a token for any account. |
| `DATABASE_URL` | Without it the app uses a SQLite file, which on a container host is wiped on every redeploy, taking accounts, missions and scans with it. |

```bash
python -c "import secrets; print(secrets.token_hex(32))"
```

If the deployment really is a single box with a persistent disk, SQLite is a
legitimate choice — say so with `ALLOW_SQLITE=1` rather than being told twice.

### Everything else

| Variable | Default | Notes |
| --- | --- | --- |
| `APP_ENV` | `development` | `production` turns on the boot checks and disables `AUTO_CREATE_TABLES` |
| `PORT` | `5000` | |
| `LOG_LEVEL` | `INFO` | |
| `LOG_JSON` | `0` | On for a log aggregator; off for a human at the edge of a field |
| `CORS_ORIGINS` | *(any)* | Comma-separated allowlist. Only matters for the Flutter **web** build — the mobile app does not enforce CORS |
| `PROXY_COUNT` | `0` | Set to `1` behind Railway/nginx/Cloudflare so `X-Forwarded-*` is trusted. **Leave 0 when reached directly**, or any client can forge its source address and get a fresh rate-limit quota |
| `MAX_UPLOAD_MB` | `32` | Hard body limit, enforced before anything is buffered |
| `LIVE_STREAM_MAX_VIEWERS` | `8` | Concurrent MJPEG viewers; each holds a worker thread |
| `GUNICORN_THREADS` | `24` | Must stay well above the viewer cap |
| `REQUIRE_AUTH` | `0` | Off by default **on purpose**: on a closed field network the operator registers cameras and flies before signing in, so most endpoints tolerate anonymous calls. Turn it on for an internet-reachable backend and every `jwt_optional_lenient` endpoint answers 401 without a valid token. `/healthz` and `/readyz` stay open |
| `RATELIMIT_ENABLED` | `1` | |
| `RATELIMIT_SIGNIN` / `_SIGNUP` / `_PASSWORD_RESET` | `10` / `5` / `5` | Attempts per IP per `RATELIMIT_WINDOW_S` (default 300 s) |
| `AUTO_CREATE_TABLES` | dev `1`, prod `0` | See migrations below |
| `MAVLINK_URL` | `udpin:0.0.0.0:14550` | `udpin:` means *we listen* — what a SITL sim streams into |
| `MAVLINK_SOURCE_SYSTEM` | `255` | Change to `254` if Mission Planner watches the same vehicle |

---

## Database migrations

The schema is managed with Flask-Migrate. `db.create_all()` only ever CREATEs —
it never ALTERs an existing table, so a column added later would simply never
appear and every query against it would fail at runtime. Production therefore
defaults to `AUTO_CREATE_TABLES=0`.

```bash
cd backend/my_flask_app
export FLASK_APP=run.py

flask db upgrade                      # apply migrations (run on every deploy)
flask db migrate -m "what changed"    # after changing a model
```

`migrations/versions/c9428fb30df7_initial_schema.py` is the baseline, generated
from the current models and verified to leave no drift.

**On an existing database that predates migrations**, stamp it before the first
upgrade so Alembic does not try to create tables that are already there:

```bash
flask db stamp c9428fb30df7
```

---

## Health checks

| Endpoint | For | Checks |
| --- | --- | --- |
| `GET /healthz` | Liveness probe | The process is up. **Nothing else** — a supervisor must not restart a healthy server mid-flight because a camera is unplugged |
| `GET /readyz` | Readiness probe | The database is reachable; 503 when not |
| `GET /api/system/health` | The operator | Every module's own view of itself |

---

## What the logs look like

```
16:07:13 INFO    [768725d980fb] agrivision: GET /api/capture/cameras/1/stream -> 200 (streaming)
16:07:28 INFO    [32efa71a2c99] agrivision: POST /api/capture/cameras/1/analyze -> 200 in 0ms
16:07:36 WARNING [ec557c383da0] agrivision: GET /api/capture/cameras/1/frame -> 504 in 6016ms
```

The bracketed value is a request id. It is echoed in the `X-Request-ID` header
and included in every error body, so an operator's screenshot points straight at
the log lines that explain it. An inbound `X-Request-ID` is kept, so a trace
started upstream is not renamed here.

A relayed stream is marked `(streaming)` rather than given a duration — it is a
response that never ends by design, and a "duration" would read as a hang.

Unhandled exceptions log a full traceback and return the request id to the
client. The exception text stays in the log, which is ours: it can carry a
database URL or a camera password.

---

## The mobile app

`BASE_URL` in `Frontend/agri_vision/assets/.env` is the one place the backend
address is set. For a single run:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5000
```

`GET /api/system/links` reports the addresses this backend is reachable on,
which is what the Settings screen shows so an operator can read the address off
one device and type it into another.

**Cleartext HTTP** is permitted by
`android/app/src/main/res/xml/network_security_config.xml`. This is deliberate
and documented there: a ground station at `192.168.x.x` has no domain name and
cannot hold a publicly trusted certificate. Android's config cannot express
"permit cleartext to RFC1918 only" — `<domain>` takes hostnames and IP
literals, not CIDR ranges — so this cannot be narrowed further and still work
on a LAN. **A public backend must be HTTPS**, and that file should then be
changed to `cleartextTrafficPermitted="false"`.

---

## Running the tests

```bash
cd backend/my_flask_app && python -m pytest tests -q
```

```bash
cd Frontend/agri_vision && flutter test
```
