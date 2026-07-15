# Google Sign-In setup

The code for Google Sign-In is done (button on the sign-in screen, backend
`/api/auth/google`). To make it actually authenticate you must create OAuth
credentials in Google Cloud — this is the only step that can't be done in code,
because the credentials are tied to your Google project.

## 1. Create OAuth credentials

1. Go to <https://console.cloud.google.com/> → create/select a project.
2. **APIs & Services → OAuth consent screen** → configure (External, add your
   email as a test user).
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**:
   - **Web application** — add authorized JavaScript origin
     `http://localhost:5959` (the dev web port) and your prod origin.
     Copy this **Web client ID**.
   - **Android** (only if you build the Android app) — package name
     `com.example.agri_vision` + your signing SHA-1
     (`keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore`,
     password `android`).

## 2. Give the app the client IDs (no secrets in the repo)

Client IDs are read from `--dart-define`, like `API_BASE_URL`:

```powershell
# Web
flutter run -d chrome --web-port 5959 `
  --dart-define=GOOGLE_WEB_CLIENT_ID=XXXX.apps.googleusercontent.com

# Android (serverClientId = the *Web* client ID, so the ID token audience
# matches what the backend verifies)
flutter run `
  --dart-define=GOOGLE_SERVER_CLIENT_ID=XXXX.apps.googleusercontent.com
```

You can pass both defines together, and combine with `API_BASE_URL`.

> Web also accepts the client ID via a meta tag in `web/index.html`:
> `<meta name="google-signin-client_id" content="XXXX.apps.googleusercontent.com">`
> The `--dart-define` above is equivalent and keeps the ID out of the HTML.

## 3. Tell the backend which audience to trust

Set `GOOGLE_CLIENT_ID` (the same Web client ID) in the backend environment so it
rejects tokens minted for other apps. Put it in `backend/my_flask_app/.env`:

```
GOOGLE_CLIENT_ID=XXXX.apps.googleusercontent.com
```

`create_app()` loads `.env` automatically. If `GOOGLE_CLIENT_ID` is unset the
backend still verifies the token with Google but skips the audience check
(fine for local testing, tighten before production).

## How it flows

```
[Continue with Google] → GoogleAuth.obtainIdToken()  (google_sign_in)
    → POST /api/auth/google { id_token }
    → backend verifies with Google, find-or-creates the user, returns JWT
    → app stores JWT + user (same as email/password sign-in)
```

Until step 2 is done, tapping the button on web shows a clear
"Google Sign-In is not configured" message instead of failing silently.
