# Production hardening and validation — 22 October 2026

## Changes

- Production/profile configuration uses only the bundled, validated HTTPS API URL. Saved server overrides and developer preferences from older builds cannot redirect the app.
- Production has no server-selection/developer routes or version-tap unlock. Connection failures offer retry; missing configuration gives an update/support message. Debug builds retain local development tools.
- Release builds reject a missing, HTTP, or credential-bearing API URL. Tagged CI releases require signing and valid HTTPS API/site configuration. Flutter is pinned to 3.47.7; CI forwards optional crash reporting and a source-revision URL.
- Development OTP hints and simulated-catalogue copy are debug-only.

## Backend coverage

The full suite passes **219 tests**, including the added tests in `backend/test/rbac_matrix.test.js` and `backend/test/database.test.js`.

The router currently registers 339 routes: 35 public, 19 staff-user, 252 gym-scoped, and 33 member routes. New HTTP integration checks exercise:

- Anonymous rejection across all 304 protected routes.
- Member-token rejection across all 271 staff/gym routes and owner-token rejection across all 33 member routes.
- Cross-gym owner rejection across all 252 gym routes.
- Denial of routes requiring permissions absent from manager, staff, and trainer roles.
- Permission changes and staff removal taking effect on existing tokens; the owning account retaining access.

These middleware checks supplement existing positive and negative business-flow tests; they do not prove every possible input or device workflow.

New disposable, file-backed SQLite tests check nested transaction/counter rollback, collection and tenant boundaries, soft deletion, integrity and foreign keys after reopening, and owner/member sessions surviving an API restart. They preserve actual finance records and completed workout data, reject stale sync writes, and verify the real backup CLI while the API is running. Existing tests also cover migrations, encrypted backup round trips, billing/webhooks, memberships, delivery, account/privacy, trainer scope, and file access.

No existing gym database is reset or seeded by these checks. Fixtures use in-memory databases or temporary directories removed at test completion.

## App coverage

The full Flutter suite passes **209 tests**. After the final configuration-constructor cleanup, the 7 new configuration/navigation tests also pass on a targeted rerun. Layout checks exercise the new update fallback on a small phone, landscape, and tablet at double text scale with animations disabled in both themes.

`flutter analyze --no-pub` reports **no issues**. The CI YAML parses and `git diff --check` passes. Actual Gradle release dry runs reject missing, HTTP, and credential-bearing API addresses with the intended HTTPS-endpoint error before configuring all plugin subprojects. This verifies the build guard, not a signed production bundle.

New configuration and widget tests cover production endpoint locking, old saved development settings, rejected invalid endpoints, debug-only local development, direct navigation attempts, the removed hidden unlock, retry behavior, and a misconfigured-build fallback.

Use these commands to reproduce the app checks with Flutter 3.47.7 / Dart 3.13.5:

```sh
source tool/env.sh
flutter analyze
flutter test
cd backend
npm test
```

## Outstanding deployment evidence

The backend is not deployed yet, as confirmed by the owner. Production must supply the real domain with `--dart-define=API_BASE_URL=https://<deployed-api-domain>`. Do not ship a placeholder address.

No Android device was connected during this pass. Real-device installation, real OTP delivery, Razorpay transactions, production recovery/alerts, Play review, and billing-policy decisions still require staging/production setup. Automated tests use development fixtures and mocked provider responses; they do not demonstrate live-provider readiness. See `docs/PRODUCTION_PLAN.md` for the remaining rollout gates.
