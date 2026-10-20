# Changelog

## [2.0.2] - 2026-10-21

Security hardening from the pre-launch audit.

### Fixed
- **Trainer scope**: a trainer's member export is limited to their own members and hides what members chose to hide, with no money column; the dashboard no longer shows a trainer gym-wide dues, billing or other members' names; the workout and diet generators refuse members who are not theirs and never use health data a member hid from trainers.
- **Subscriptions**: buying a plan no longer grants a higher tier for time that was not paid for or removes paid time. Same-tier purchases renew, upgrades are prorated from what was actually paid, downgrades queue until the current plan ends. Delivery uses the plan as sold and the amount confirmed by the payment.
- **Free trial**: one trial per owner is claimed when a gym is created; extra gyms are allowed (up to 10 per account) but wait for a plan. Referring your own gym earns nothing.
- **Sign-in codes**: failures are counted per phone across all codes with escalating lockouts (15 min up to 4 h); locked or unknown numbers look identical; codes that fail all read the same.
- **Text-message cost**: per-phone, per-address, per-account, per-gym-QR and global sending budgets, tighter limits on the public endpoints, an optional bot challenge (Cloudflare Turnstile), and an operator alert before the global ceiling is reached.
- **Account enumeration**: login, registration and every resend answer a known and an unknown number alike.
- **Payments and messages**: a payment of the wrong amount, or a second payment for a settled order, alerts the operator; operator commands to apply or close such orders; messages stuck in sending are failed and refunded once, never re-sent.
- **Files**: a trainer reads only the gym logo, colleagues' profile photos and the photos of members assigned to them (not ID cards, documents or other uploads); other gyms, members and anonymous callers were already refused and are now covered by tests.
- Anonymous requests are no longer read before sign-in is checked and have small body limits and a request budget; malformed URLs, `sort=__proto__` and non-object bodies return 4xx instead of 500; file storage quota per gym; device keys are rate limited and device clocks are not trusted; old sign-in records and sessions are purged; changing a sign-in number signs out other devices.
- `node src/seed.js --reset` works again and refuses production or any database with real accounts.
- Tests that used the UTC date for Indian gyms failed for 5.5 hours every day.

### Added
- Encrypted off-site backups with a public key (`backend/scripts/backup-crypt.js`), key-management and restore-drill documentation.
- Operator console: `events`, `mismatches`, `order-apply`, `order-dismiss`, `recover-messages`.
- Separate `SEAL_KEY` and `ACCESS_CODE_KEY` so `JWT_SECRET` can be rotated.

### Changed
- `ALLOW_TEST_PAYMENT_KEYS=1` (staging only, off by default) lets a production-mode server accept a gym's Razorpay test keys and then refuses live ones; it cannot start with live platform keys or on a database that holds live gym payment accounts.
- Deployment guide: environment reference, staging rules, tested rollback procedure; release guide: which key signs a release and how to verify it; CI passes `SITE_URL` to release builds and runs with read-only repository permissions.
- Removed the unused Firebase packages: the app no longer declares advertising-ID, ad-services, push or install-referrer permissions.

## [2.0.1] - 2026-10-12

Production readiness.

### Added
- `docs/PRODUCTION_CHECKLIST.md`, the ordered list to tick before launch.
- `backend/scripts/smoke.js`: post-deploy check that production switches are off and the edges are closed (HTTPS, CORS, forged webhook, auth, body size).
- `deploy/offsite-backup.sh` (rclone to any S3-compatible bucket) and `deploy/healthcheck.sh` (down, disk, stale backup, optional webhook alert).
- `tool/make-upload-keystore.sh` creates the Play upload key and `android/key.properties`.

### Changed
- "Save Contact" on a member is now "Copy phone number"; the app no longer asks for or declares the contacts permission.
- Version tags now start CI, and the signed-bundle job reads the keystore from the path the Gradle build expects.

## [2.0.0] - 2026-10-11

Gymmie 2.0 is the first version that can take a paying gym: a member app, real billing and delivery, a new look, and a clean break from
the original project's identity. The application id is now `app.gymmie.android` (a new app, not an update of 1.x).

### Added
- **Member app** (native Flutter, offline-first): a training log ported from openGym (plan, live workout, history, stats, activity heatmap, exercise library,
  body map, "Choose a focus"), all of openGym's applicable settings, workout reminders, backup export and import, and local-first sync to the gym's server.
- **Member account and privacy**: edit profile and photo, change phone number, signed-in devices, notifications, what a trainer may see, training-summary sharing,
  membership requests (renew / change plan / cancel) with an owner/manager inbox, account deletion with retention rules.
- **Membership at a glance**: plan, status, start and expiry, days left, visits this month, price paid and balance, payment status, renewal, and "Pay online".
- **One sign-in for everyone** (phone + one code; the server says whether the number is staff, a member, or both) and a dedicated **Member login** with
  gym-specific **access codes** that the gym issues, re-issues or revokes. "Welcome to <gym>!" after sign-in.
- **Launch flow**: animated logo, a skippable walkthrough invitation for new owners and managers (contact details only from server configuration), and an
  optional "collect fees online" step with "Skip for now".
- **14-day free trial**, once per owner, starting when setup is complete and kept on the server; a banner shows the days left.
- **Billing**: subscription plans (Starter, Growth, Pro) enforced on the server (read-only for 7 days after the end, then billing only), plan-based add-ons and
  limits, Razorpay payment links with a signed idempotent webhook, GST invoices for Gymmie's own sales, referral rewards, message-credit packs.
- **Gyms collect their own fees**: a gym connects its own Razorpay account (keys verified and sealed), creates payment links for a member's dues, and the gym's
  own webhook records the payment. Separate from the Gymmie subscription.
- **Real delivery**: sign-in codes and gym messages by SMS (MSG91), WhatsApp (Cloud API) and email (Resend); a failed message returns its credit.
- **Exercise pictures and animations** that play as in openGym, for members and owners (needs a licence, see NOTICE.md).
- **Operations**: Dockerfile, Caddy (HTTPS), nightly verified backups, restore check, `/ready`, graceful shutdown, JSON logs, CI workflow, operator console
  (`backend/scripts/admin.js`).
- 5,632 openGym exercises in the default exercise library; plan benefits; trainer plans in the member app; owner view of the member-app relationship.

### Changed
- **One look**: the owner and staff app now uses the member app's palette, accent, system font and components (dark by default, light supported).
- **New identity**: Gymmie logo and launcher icon, application id `app.gymmie.android`, own `gymmie://` link scheme (older printed `dgymbook://` ID cards still scan),
  licence AGPL-3.0, recovered third-party assets removed.
- Trainers see only the members assigned to them and, in those, only what each member allows (memberships and PAR-Q forms included).
- Release builds are minified and obfuscated and refuse to be signed with the debug key.

### Fixed
- Several screens did not repaint when a theme or setting changed behind another page.
- Merging two phones with different weight units read one phone's numbers in the other's unit.
- Debug builds no longer need a release key; the release guard applies to release tasks only.
- The Backend URL and WhatsApp screens no longer describe a "reconstruction"; the WhatsApp banner now reflects the provider the server really uses.
- A long access code scales to fit its dialog instead of wrapping mid-code.

### Tests
- 129 backend end-to-end and 202 Flutter tests (including golden tests of the member domain against openGym's own JavaScript).

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
