# Publishing AgriVision on Google Play

What was changed to make the app acceptable to Google Play, what was verified,
and the steps that only the account owner can do. Work through section 3 in
order; everything in it is required before the first upload.

---

## 1. What the app now does for Play

| Requirement | Where it is met |
|---|---|
| A real package name (Play rejects `com.example.*`) | `com.mpcst.agrivision` in `android/app/build.gradle.kts` |
| Signed with an upload key, not the debug key | Release signing reads `android/key.properties`; `flutter build appbundle` **refuses to run** without it |
| Current target API level | Target SDK 36, minimum 24 (from Flutter 3.35) |
| 16 KB memory page size | Every native library passes `zipalign -c -P 16` (verified on the release build) |
| Privacy policy, on a public URL | `https://agrivision-production-ae8e.up.railway.app/privacy` |
| Privacy policy reachable **inside** the app | Settings → Privacy policy, and the link on the sign-up screen |
| Account deletion **inside** the app | Settings → Delete account (asks for the email address to confirm) |
| Account deletion **on the web**, without reinstalling | `https://agrivision-production-ae8e.up.railway.app/account/delete` |
| Reporting AI-generated content in-app | Report button on every crop-advisor answer; stored in `advisor_reports` |
| A release build that works on a real phone | Release builds refuse `127.0.0.1` / `10.0.2.2` and use the deployed backend |

The release build declares exactly these permissions (read from the merged
manifest, not assumed):

| Permission | Why |
|---|---|
| `INTERNET` | Talking to the backend |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | The "you are here" pin on the mission map. Foreground only; there is no background location, so no location declaration form is needed |

There are no photo, video or storage permissions: gallery access goes through
Android's system picker, which needs none. So the Photo and Video Permissions
declaration does not apply. (The merged manifest also lists
`com.mpcst.agrivision.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; that is an
internal, signature-level permission added by AndroidX, not one users are asked
for.)

---

## 2. Decide before the first upload

**The package name is permanent.** Once a build is uploaded, Play will never
accept a different package name for that listing. It is set to
`com.mpcst.agrivision`. If this is being published as an **official MPCST /
Government of Madhya Pradesh app** from a verified government developer
account, change it now to something like `in.gov.mpcst.agrivision` — in
`android/app/build.gradle.kts` (`applicationId` and `namespace`) and by moving
`MainActivity.kt` to the matching folder. Do not use a `gov.in` name from a
personal account: Play treats an app that implies official government status
without verification as misrepresentation.

---

## 3. Steps only the account owner can do

### 3.1 Fill in the legal documents

`backend/my_flask_app/app/legal/privacy_policy.md` and `terms.md` contain
placeholders in square brackets: organisation name, contact email, postal
address, effective date, email provider, backup retention, and jurisdiction.
Replace them, then copy both files over the app's copies:

```bash
cp backend/my_flask_app/app/legal/*.md Frontend/agri_vision/assets/legal/
```

A test fails if the two copies differ, so the page Google reviews and the page
a farmer reads in the app cannot drift apart. **Have someone qualified review
both documents.** They were drafted from what the code actually does, but they
are legal documents.

### 3.2 Configure and deploy the backend

1. On Railway, set `SUPPORT_EMAIL` to the address that handles deletion
   requests. The web deletion page shows it to people who signed up with Google
   and therefore have no password to enter.
2. Push to `main`. The deploy runs `flask db upgrade`, which creates the
   `advisor_reports` table. The `/privacy` and `/account/delete` pages must be
   live before you submit: Google checks them.
3. Rotate the Gemini API key if you have not already. It was pasted in plain
   text during development.

### 3.3 Create the upload key

Once, and keep it safe. **If this key is lost, you cannot update the app.**

```bash
keytool -genkey -v -keystore %USERPROFILE%\agrivision-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `Frontend/agri_vision/android/key.properties` (already git-ignored,
as is every `*.jks`):

```properties
storePassword=
keyPassword=
keyAlias=upload
storeFile=C:/Users/<you>/agrivision-upload.jks
```

Use forward slashes in `storeFile`; a backslash is an escape character in a
`.properties` file. Back up the `.jks` and both passwords somewhere other than
this computer and this repository, and record them in `docs/ACCOUNTS.local.md`.

### 3.4 Fix Google Sign-In for the new package name

Changing the package name means **Google Sign-In will fail on the release app**
(error 10, `DEVELOPER_ERROR`) until Google Cloud knows about it. In Google Cloud
Console → APIs & Services → Credentials, create an **Android** OAuth client for
`com.mpcst.agrivision` with each of these SHA-1 fingerprints:

* the upload key: `keytool -list -v -keystore %USERPROFILE%\agrivision-upload.jks -alias upload`
* the Play app signing key: Play Console → your app → Test and release → App integrity → App signing key certificate

The second one only exists after the first upload, which is why sign-in
commonly works in local tests and fails for everyone installing from Play.

### 3.5 Build the bundle

```bash
cd Frontend/agri_vision
flutter build appbundle --release --dart-define=API_BASE_URL=https://agrivision-production-ae8e.up.railway.app
```

The output is `build/app/outputs/bundle/release/app-release.aab`. The
`--dart-define` is belt and braces: a release build already refuses a
device-local address, but naming the backend explicitly means the bundle never
depends on whatever `assets/.env` last said.

**Every upload needs a higher build number.** Bump the number after the `+` in
`pubspec.yaml` (`version: 0.1.0+1` → `0.1.0+2`) before each build you upload.

---

## 4. Play Console: the forms

### 4.1 App content

| Section | Answer |
|---|---|
| Privacy policy | `https://agrivision-production-ae8e.up.railway.app/privacy` |
| App access | Sign-in is required. Give reviewers a working test account and say that phone photo scanning works without a drone; the drone screens need MAVLink hardware |
| Ads | No ads |
| Content rating | Complete the questionnaire. No violence, sexual content, gambling, or user-to-user communication |
| Target audience | 18 and over |
| News app | No |
| Government app | No, unless published by a verified government account (see section 2) |
| Financial features | None |
| Health | None |
| Data safety | Section 4.2 |
| Account deletion URL | `https://agrivision-production-ae8e.up.railway.app/account/delete` |

### 4.2 Data safety

Answers derived from the code. Re-check them whenever a feature starts sending
something new.

* Does the app collect or share user data? **Yes**
* Is all data encrypted in transit? **Yes.** The hosted backend is HTTPS. Traffic to a ground station on the user's own local network is plain HTTP, but that is the user's own device, not the developer collecting data.
* Can users request that their data be deleted? **Yes**, in the app and at the deletion URL.

| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Personal info: Name | Yes (username; name from Google Sign-In) | No | No | Account management |
| Personal info: Email address | Yes | No | No | Account management, password reset |
| Personal info: Phone number | Yes | No | Yes | App functionality (profile) |
| Personal info: Other info | Yes (organisation, role, typed location, pilot licence details) | No | Yes | App functionality |
| Photos | Yes | **Yes, with Google** when the user asks the crop advisor | No | App functionality |
| Other user-generated content | Yes (missions, field boundaries, surveys, spray plans, advisor reports) | No | No | App functionality |
| Location | **No.** The phone's location is used on the device only and never sent | No | | |
| App activity, app info and performance, device IDs | **No.** There is no analytics, crash reporting or advertising SDK | No | | |

Photos are declared as **shared** on purpose. The advisor sends a photo to
Google's Gemini API, and on its free tier Google's terms allow it to use that
content to improve its services. That goes beyond a service provider acting
purely on your behalf, so declaring it as shared is the accurate answer.

### 4.3 Store listing

* **App name** (30 characters max): `AgriVision – Crop Scouting`
* **Short description** (80 max): `Spot crop disease from a photo or drone survey and spray only where needed.`
* **Full description** (a draft to edit):

  > AgriVision helps farmers and drone operators in Madhya Pradesh find crop
  > problems early and treat only the part of the field that needs it.
  >
  > **Scan with your phone.** Pick your crop, photograph an affected leaf, and
  > get a likely diagnosis, how severe it looks, and what is usually sprayed for
  > it, with the dose per acre and the waiting period before harvest.
  >
  > **Fly a survey.** With a compatible drone (ArduPilot or PX4, over MAVLink)
  > and a camera, AgriVision scans the crop as the drone flies, maps where the
  > problems are, and builds a targeted spray plan that the drone flies only
  > after you have filled the tank and given permission.
  >
  > **Ask the crop advisor.** Get answers to follow-up questions about a scan,
  > in English or Hindi.
  >
  > AgriVision is decision support, not a prescription. Always confirm a
  > problem in the field and follow the product label and your local KVK for
  > the dose, crop stage and pre-harvest interval.

* **Graphics:** a 512 × 512 PNG icon (generate one from `tool/generate_app_icons.py`), a 1024 × 500 feature graphic, and at least two phone screenshots (`docs/manual/img` has current ones).
* **Category:** Tools.

---

## 5. Testing before production

**New personal developer accounts** must run a closed test before they can
publish to production. At the time of writing the rule is at least 12 testers,
opted in continuously for 14 days. Organisation accounts are exempt. Check the
current rule in Play Console under Test and release, because Google has changed
it before.

The usual order is: Internal testing (instant, up to 100 testers) → Closed
testing (to meet the rule above) → Production.

---

## 6. Known limitations to be honest about

* **Cleartext HTTP is permitted** so the app can reach a ground station on a
  field LAN (`192.168.x.x`), which has no public address and cannot hold a
  trusted certificate. Android cannot scope cleartext to private IP ranges, so
  it is allowed app-wide. Play does not reject this, but its pre-launch report
  may flag it. The deployed backend itself is HTTPS.
* **The crop model is decision support.** It is 88% accurate on the maize test
  set and weaker on field photographs than on lab images; the app and the terms
  both say so.
