# Gymmie (reconstruction of DGymBook Partner 1.9.4)

Flutter app (`com.dgymbook.app`, package `gym_book_app`, version `1.9.4+1178`) plus a **development backend**.

> **What this is, honestly.** The original APK is Dart-AOT compiled and obfuscated; no Dart source or backend source
> exists in the bundle. Only string literals, assets, native resources, the manifest and the Firebase/Sentry wiring
> could be *recovered*. All Dart code and the whole backend are *reconstructed* from that evidence. Nothing here is
> the original source and the backend is **not** the original DGymBook service.

## Recovered vs reconstructed

| Area | Status |
|---|---|
| Assets (fonts, Lottie, posters, sounds, icons, splash colour), applicationId, permissions, deep links | **Recovered** from the bundle |
| UI copy, validation messages, API path inventory, analytics event names, constants | **Recovered** (`docs/evidence/`, scrubbed of secrets) |
| Layouts, navigation, state management, data models, all Dart code | **Reconstructed** from the above and the recovered screenshots |
| Backend (`backend/`) | **Reconstructed dev stand-in**; contract in `docs/API_CONTRACT.md`, generated route list in `docs/API_ROUTES.md` |

No production credentials, endpoints or keys were recovered or invented. Firebase and Sentry are opt-in via
`--dart-define` (`FIREBASE_*`, `SENTRY_DSN`); without them the app runs with both disabled.

## Dev-backend stand-ins (not the real services)

OTP delivery (fixed dev OTP, refused in production mode), payment provider, WhatsApp/SMS outbox, rule-based workout /
diet / PAR-Q generators (labelled "rule-based", not AI), biometric device callback API (no physical device).
Auth is HS256 JWT + rotating refresh tokens, per-gym tenancy, role/permission matrix enforced server-side.

## Run

See `docs/BUILD.md`. Short version: `source tool/env.sh`, start `backend` (`node src/seed.js --reset && node src/server.js`),
then `flutter run`. Debug builds reach the host backend at `http://10.0.2.2:8787`.

## Verified (2026-10-09)

`flutter analyze` — no issues · `flutter test` — 20 pass · `backend npm test` — 38 pass ·
`flutter build apk --debug` and `--release` succeed (logs in `docs/build-logs/`). Screens exercised on an Android emulator
against the seeded backend.

## Optional modules (admin switches)

Attendance, the home-screen "Members in gym" card and Biometric devices are **off by default**. The owner or a manager turns them on
under *Settings → App Features → Attendance & Access*. These three flags are additions of this reconstruction (not in the original
catalog). They hide the UI (home cards, quick actions, Settings entries, routes); they are a display preference, not an access-control
boundary: server permissions are unchanged. Restart the dev backend after pulling this change so it loads the new catalog.

## Member ID card

*Member menu → Generate ID card*: preview with photo, ID, plan validity, assigned labels and a check-in QR (same payload as
"Show member QR"). Pick a colour theme, assign or create labels (saved to the member), and share the card as a PNG.

## Name

The app is shown as **Gymmie** (launcher label, title, login/splash/invoice text). The Android applicationId (`com.dgymbook.app`),
the `dgymbook://` deep-link scheme and the Dart package name are unchanged so existing links, QR codes and installs keep working.
The launcher icon is the original dumbbell mark; it contains no name.

## Known gaps — see `docs/FEATURE_MATRIX.md`

Report-schedule settings page, `app_links` payment deep-link handler (manifest filter exists), FCM token registration
(needs a real Firebase project), `view-photo` route, partial localisation (English + a Hindi subset), and widget tests beyond
unit/bloc coverage.

## Release signing

`android/app/build.gradle.kts` signs with `android/key.properties` if present. Otherwise the release APK is signed with the
**debug key** and the build prints a warning — not suitable for the Play Store. Create your own keystore and `key.properties`.

## Environment changes made

Installed Flutter 3.47.7 (arm64), JDK 21 and the Android SDK under `~/development`. The Android SDK licences were accepted on the
user's behalf as part of the instruction to install the toolchain; review them if that matters to you.

## Install on a phone over USB (e.g. iQOO 13)

The release build only allows HTTPS, and the dev backend is plain HTTP, so use the debug build and tunnel the backend over USB:

```bash
cd backend && node src/seed.js --reset && node src/server.js &      # dev backend on :8787
flutter build apk --debug --target-platform android-arm64 --dart-define=API_BASE_URL=http://127.0.0.1:8787
adb reverse tcp:8787 tcp:8787                                       # phone's 127.0.0.1:8787 -> your computer
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Enable Developer options and USB debugging on the phone first. Log in with `9000000001` and the dev OTP from `docs/BUILD.md`.
`flutter build apk --release --target-platform android-arm64` gives a smaller build for use against an HTTPS backend (set its URL in Developer tools).
