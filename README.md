# DGymBook Partner 1.9.4 — reconstruction

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

`flutter analyze` — no issues · `flutter test` — 18 pass · `backend npm test` — 37 pass ·
`flutter build apk --debug` and `--release` succeed (logs in `docs/build-logs/`). Screens exercised on an Android emulator
against the seeded backend.

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
