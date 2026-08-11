# Google Sign-In setup

`lib/src/core/utils/google_auth.dart` obtains a Google ID token and the backend
verifies it at `POST /api/auth/google`. This is how to make that work on
Android, which is where it usually fails.

## The error you will hit first

```
PlatformException(sign_in_failed,
  com.google.android.gms.common.api.ApiException: 10, null, null)
```

**ApiException: 10 is `DEVELOPER_ERROR`.** It is not a code bug and not a
network problem. Google Play Services refused the request because the app that
asked is not one it recognises. It means one of exactly three things:

1. there is no **Android** OAuth client for this app in the Google Cloud
   project, or
2. one exists but its **package name** does not match the app's
   `applicationId`, or
3. one exists but its **SHA-1 fingerprint** does not match the certificate the
   APK was signed with.

Setting `GOOGLE_WEB_CLIENT_ID` alone is *not* enough on Android. The web client
ID is what makes Google issue an **ID token** with the right audience for the
backend to verify; the Android client is what makes Google agree to sign you in
at all. You need both, in the same Cloud project.

## What this app currently is

| | Value |
|---|---|
| `applicationId` / `namespace` | `com.example.agri_vision` (`android/app/build.gradle.kts`) |
| Web client ID | `GOOGLE_WEB_CLIENT_ID` in `Frontend/agri_vision/assets/.env` |
| `google-services.json` | not present — **not required** for `google_sign_in`; it is required only if you add Firebase |

## 1. Get your signing fingerprint

Debug builds (`flutter run`) are signed with the shared debug keystore:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

On Windows the keystore is at `%USERPROFILE%\.android\debug.keystore`. Copy the
`SHA1:` line.

Release builds are signed with **a different key**, so a build that works in
debug will fail with the same ApiException: 10 once signed for release. Add the
release SHA-1 as a second Android client (or a second fingerprint on the same
one). If you ship through Play App Signing, the fingerprint that matters is the
one under *Play Console → Setup → App signing*, not your upload key.

## 2. Create the Android OAuth client

In the **same Google Cloud project** that owns your web client ID
(<https://console.cloud.google.com/apis/credentials>):

1. *Create credentials → OAuth client ID → Application type: **Android***
2. Package name: `com.example.agri_vision`
3. SHA-1: the fingerprint from step 1
4. Save. There is no client secret and nothing to copy into the app — Google
   matches on package name + fingerprint alone.

Also make sure the project has an OAuth consent screen configured, and that
your Google account is added as a **test user** while the consent screen is in
*Testing* mode. A signed-in account that is not a test user fails too, though
usually with a different error.

Changes can take a few minutes to propagate. Fully uninstall and reinstall the
app afterwards — Play Services caches the failure.

## 3. Point the app and the backend at the web client ID

`Frontend/agri_vision/assets/.env` (gitignored):

```env
GOOGLE_WEB_CLIENT_ID=xxxxxxxx-xxxxxxxxxxxx.apps.googleusercontent.com
```

Backend `.env`:

```env
GOOGLE_CLIENT_ID=xxxxxxxx-xxxxxxxxxxxx.apps.googleusercontent.com
```

**These two must be the same value.** The client ID becomes the `aud` claim of
the ID token, and the backend rejects a token whose audience is not its own
`GOOGLE_CLIENT_ID`. Use the **Web application** client ID in both places —
including on Android, where it is passed as `serverClientId`. Using the Android
client ID here yields no ID token at all, which surfaces as *"Google did not
return an ID token"* rather than ApiException: 10.

## About `com.example.agri_vision`

`com.example.*` is the Flutter template default. It works for development, but
Google Play will not accept it, so the package name has to change before
release — and changing it invalidates the Android OAuth client above. Do it
before registering the fingerprints if you can:

- `android/app/build.gradle.kts` — `namespace` and `applicationId`
- `android/app/src/main/AndroidManifest.xml`
- the Kotlin/Java source directory under `android/app/src/main/kotlin/…`

## Checklist when it still fails

| Symptom | Cause |
|---|---|
| `ApiException: 10` | Android OAuth client missing / wrong package name / wrong SHA-1 |
| `ApiException: 12500` | consent screen not configured, or account not a test user |
| `ApiException: 7` | no network |
| `sign_in_canceled` | the user dismissed the picker — not an error |
| "Google did not return an ID token" | `GOOGLE_WEB_CLIENT_ID` unset, or an Android client ID used instead of the web one |
| Backend answers 401 on `/api/auth/google` | backend `GOOGLE_CLIENT_ID` ≠ the app's `GOOGLE_WEB_CLIENT_ID` |

Web builds need only `GOOGLE_WEB_CLIENT_ID`, plus the page's origin listed under
*Authorised JavaScript origins* on the web client.
