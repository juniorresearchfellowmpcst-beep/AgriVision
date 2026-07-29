# Frontend ↔ backend module map

Every screen in the Flutter app and the backend module behind it. Use this to
check at a glance whether a feature is real or still a placeholder.

## Status

| Frontend module | Backend | Endpoint(s) |
|---|---|---|
| Sign in / up, Google, OTP reset | `auth_service.py` | `/api/auth/*` |
| Home — drone status, recent missions | `drone_service.py`, `mission_service.py` | `/api/drones/status`, `/api/mission/missions` |
| Mission Planning — KML → survey path | `mission/` (kml, planner) | `/api/mission/upload-kml` |
| Mission Planning — save / history | `mission_service.py` | `/api/mission/missions` |
| Mission launch, live telemetry | `mavlink/` | `/api/mavlink/*` — see [MAVLINK_SITL.md](MAVLINK_SITL.md) |
| Analysis — multispectral run | `preprocessing/` | `/api/preprocessing/analyze-images` |
| Reports — history | `analysis_service.py` | `/api/analysis/reports` |
| **Reports — export PDF / CSV** | `report_export.py` | `/api/analysis/reports/<id>/export` |
| Alerts | `analysis_service.py` | `/api/analysis/alerts` |
| Disease — scan a leaf | `disease_service.py`, `ai/` | `/api/disease/identify` |
| **Disease — scan history** | `disease_service.py` | `/api/disease/scans` |
| Profile — identity + flight stats | `user_service.py` | `/api/users/me` |
| **Profile — pilot credentials** | `credential_service.py` | `/api/credentials` |
| **Profile / Settings — toggles** | `user_service.py` | `/api/users/me/preferences` |
| **Settings — sync queue** | `user_service.py` | `/api/users/me/sync-status` |
| Settings — drone pairing | `drone_service.py` | `/api/drones/pair` |

**Bold** rows were added when these screens were still rendering hard-coded
sample data. The rest were already wired.

---

## The modules added to close those gaps

### Pilot credentials — `/api/credentials`

Licences, certificates, zone clearances and insurance. A new account is seeded
with the four rows an Indian agri-drone operator is required to hold, **left
blank** — that is what an unfinished profile honestly looks like, and inventing
licence numbers would be worse than showing nothing. Tapping a row in the app
opens an edit sheet.

Status is never stored. `valid` / `expiring` / `expired` is recomputed from
`expires_on` on every read (`EXPIRING_WINDOW_DAYS = 90`), so a licence that
lapses overnight is red the next time the screen loads without any job running.

```
GET    /api/credentials        list + expiring_count + expired_count
POST   /api/credentials        add one
PUT    /api/credentials/<id>   edit (send expires_on: null to clear it)
DELETE /api/credentials/<id>   remove
```

All require a login — there is no anonymous view of somebody's licence numbers,
and one pilot cannot read or edit another's (403).

### Preferences — `/api/users/me/preferences`

The five toggles across Profile (Mission Updates, AI Alerts, Field Reports) and
Settings (Auto Sync, Push Notifications). Previously in-memory only: they reset
every time the app restarted.

Stored server-side so they follow the pilot to any device they sign in on. All
default to **on** — a new operator should hear about a problem and then turn
things down, not miss one because a toggle started off. `PUT` is a partial
update; an unknown key is **rejected**, not ignored, so a typo in the app
surfaces immediately instead of silently never taking effect. Preferences also
ride along on `GET /api/users/me` so the Profile screen renders its switches in
the same frame as the rest of the profile.

### Sync summary — `/api/users/me/sync-status`

Real per-record-type counts for the Settings screen's SYNC QUEUE (it used to
read a hard-coded 3 / 47 / 1).

`pending` counts records the **server** still considers open — a flight saved
but never closed out. It never guesses at records still sitting unsent on a
device, because the server cannot know about those. Everything else it holds is
by definition synced.

### Disease scan history — `/api/disease/scans`

`POST /api/disease/identify` now persists every diagnosis and returns a
`scan_id`. The response shape is otherwise unchanged, so the existing result
view keeps working.

This exists because a diagnosis used to vanish the moment the operator left the
screen. Knowing *when* a blight first appeared in a block is worth as much to
an agronomist as knowing it is there now. Scans record the block name (pass
`field_name` with the upload), the confidence, and which engine answered —
a heuristic and a trained model are not equally trustworthy, so history says
which one it was.

```
GET /api/disease/scans        past scans, newest first
GET /api/disease/scans/<id>   re-open one with its full diagnosis
```

### Report export — `/api/analysis/reports/<id>/export?format=csv|pdf`

The Reports tab's "Export PDF / CSV" button used to answer "coming soon".

* **CSV** — summary block plus the detections table, for a spreadsheet.
  Standard library only, so it always works.
* **PDF** — printable A4 one-pager with the risk split drawn as a bar chart,
  for the file that goes to the farm owner. Rendered with matplotlib; if that
  is not installed the endpoint answers 503 with a clear message and CSV still
  works.

Both are built from the stored `AnalysisRecord`, never by re-running the
pipeline — an exported report must show exactly what the app showed. The server
names the file (`agrivision-block-a-north-20260728.pdf`) so an export is still
identifiable months later.

In the app the button opens a format picker, then the OS save dialog via
`AttachmentDownloader` (built on `file_picker`, so no new dependency or storage
permission).

---

## Bugs fixed along the way

* **History ordering was nondeterministic.** `list_missions`, `list_records`,
  `list_alerts` and the new `list_scans` ordered by `created_at DESC` alone.
  SQLite stores that to the second, so records created in the same second came
  back in arbitrary order — and the Reports tab defaults to showing the first
  row. All four now tie-break on `id DESC`.
* **Two sources of truth for notification toggles.** `ProfileState` carried its
  own copies, so Profile and Settings could disagree about the same switch.
  `SettingsCubit` now owns them.
* **Fake identity on failure.** The Profile screen fell back to a sample pilot
  ("Raj Patel", a licence number, a phone number) when the backend was
  unreachable — indistinguishable from real data to whoever was looking at it.
  It now falls back to `PilotProfileEntity.empty()` (dashes).
* **Dead transport in `bootstrap`.** A fully configured `ApiClient` was built at
  startup and never used, because every service makes its own Dio through
  `ApiConfig`. Removed, with a note where it would go if the app ever
  centralises.
* **Latent crash in credential update.** `kind` went through the generic
  free-text loop, where a null would have hit `None.lower()`. It is validated
  separately now.

## Still placeholder

These are unused or cosmetic, and no backend was added for them:

* `EnvSettings` / `AppRepositoryImpl.getEnvSettings()` — template leftovers
  (`SURBO_*` keys) that nothing reads.
* `CoverageMapCard`, `PrecisionSavingsCard`, `FieldNotesCard` — report widgets
  that are not rendered by any screen.
* `getDummyData()` generators on `AlertEntity`, `MissionReportEntity`,
  `AssignedDroneEntity`, `ProfileActivityEntity` — no longer called anywhere,
  left in place rather than deleted as part of this change.
* `crop_routes.py` / `crop_service.py` / `crop_repository.py` — empty files, no
  frontend consumer.

## Tests

```bash
cd backend/my_flask_app && python -m pytest tests/ -q
```

`tests/test_profile_modules.py` covers the five new modules; `tests/test_mavlink.py`
covers the flight link; the rest were already there. 59 tests.
