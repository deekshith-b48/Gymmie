# Changelog

## [1.0] - 2026-10-09

First public release (in-app version `1.9.4+1178`).

### Added
- Flutter app: auth, dashboard, members and memberships, plans and pricing, finance, leads, attendance, staff and trainers,
  products and sales, fitness (workout, diet, exercises), PAR-Q forms, broadcasts and messaging, feedback, video links, poster, settings.
- Development backend (Node 22, SQLite, no npm dependencies): 278 documented routes, JWT with rotating refresh tokens,
  role-based permissions, per-gym tenant isolation, rate limiting, rule-based generators.
- Member ID cards with labels, a check-in QR and share-as-image.
- Admin switches `ATTENDANCE`, `MEMBERS_IN_GYM` and `BIOMETRICS`, off by default.
- Tests: 20 Flutter and 38 backend end-to-end; documentation (README, API contract and routes, build guide, feature matrix, recovered-evidence files).

### Changed
- App is named **Gymmie** (launcher label, title, login, splash, invoice and error text). The application id, the
  `dgymbook://` scheme and the Dart package name are unchanged.
- The membership price quote reports a start-date overlap immediately.

### Known gaps
See `docs/FEATURE_MATRIX.md`.
