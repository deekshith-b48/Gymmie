# Gymmie production rollout plan

Reviewed 22 October 2026 against commit `3842f89`. Scope: the native Flutter Android app and `backend/`, initially serving a small India pilot. This is a proposed execution plan, not deployment approval or proof of operational readiness.

## Implementation progress — 22 October 2026

The subsequent hardening pass removes production server selection and the hidden developer unlock, ignores saved endpoint overrides in production, requires a bundled HTTPS API URL for Android releases, and makes tagged CI releases fail on missing signing/configuration. Flutter is pinned to 3.47.7; release CI forwards crash/source configuration. The exact local SDK has been restored.

Validation now includes 219 passing backend tests and 209 passing Flutter tests, with additional route-wide owner/member/RBAC and file-backed database/restart/online-backup checks. See `docs/PRODUCTION_VALIDATION.md` for scope and limitations. The initial-review observations below are historical; unchecked rollout gates still require independent evidence. The backend is not deployed yet, so the production domain and live-device/provider checks remain outstanding.

## Current assessment

The repository has substantial launch infrastructure already: tenant and role enforcement, OTP abuse controls, signed payment webhooks, SQLite migrations, backup encryption, readiness checks, Docker/Caddy deployment, and Android release signing guards. Focus next on release reproducibility, real provider validation, recovery, and device testing.

- **Verified now:** `cd backend && npm test` — 209 passed, 0 failed.
- **Not verified now:** Flutter analysis/tests or a signed release build. `source tool/env.sh; flutter analyze` could not start because Flutter is absent from the configured path. README test counts are historical, not fresh verification.
- **Unknown:** deployed infrastructure, provider approvals, Play account status, signing secrets, published policies, and restore-drill results. Existing unchecked checklists do not establish that these are missing or completed.
- **Code-level gaps observed:** `.github/workflows/ci.yml` succeeds when signing secrets are absent; Flutter uses an unpinned stable channel; release build does not pass `SENTRY_DSN` or `OPENGYM_SOURCE_URL`. Member source links default to upstream openGym, so verify that shipped notices also expose the actual Gymmie source revision.

## 1. Set the release boundary and resolve distribution — start immediately

Owner: product/business owner with engineering.

- [ ] Freeze the first release to Android, owner/staff management, native member workouts, membership tracking, and the chosen messaging channels. Defer iOS, FCM, AI features, advanced workout parity, and additional countries.
- [ ] Confirm production domain, support contact, app ID, pricing, deployment budget, and expected pilot traffic. Use existing `docs/GO_TO_MARKET.md` prices as hypotheses to validate.
- [ ] Resolve Google Play billing treatment **before finalizing checkout**. The app sells Gymmie software subscriptions/credits through Razorpay and also collects physical gym membership fees. Google's payments policy generally requires Play Billing for digital app functionality/cloud services, with exceptions and eligible alternative-billing programs; physical gym memberships have a separate exception. Audit each purchase and link, then implement an eligible digital billing flow or a policy-compliant consumption-only distribution design. External checkout links are not an automatic workaround.
- [ ] Confirm Play account type and testing requirement. New personal accounts created after 13 November 2023 currently need at least 12 testers continuously opted in for 14 days before applying for production access. Recruit testers early.
- [ ] Start provider/domain verification: Razorpay KYC, selected SMS/DLT templates, WhatsApp templates if offered, verified email sender, Play identity checks.

Exit: a written scope and payment/distribution decision, named owners, and provider applications underway.

## 2. Make the release reproducible — first engineering batch

Owner: engineering. Suggested effort: 2–4 working days, subject to findings.

- [ ] Install and pin a Flutter/Dart version compatible with `pubspec.yaml`; use the same version locally and in CI. Pin backend/container versions deliberately, retaining a planned security-update process.
- [ ] Rerun `flutter pub get`, `flutter analyze`, `flutter test`, and backend tests. Fix failures before assembling a candidate.
- [ ] Make tagged release CI fail if required signing/config inputs are missing. Require HTTPS API/site URLs; validate the exact build version and signing certificate. Never print signing secrets.
- [ ] Pass the reviewed `SENTRY_DSN` and Gymmie shipped-source URL into release builds. Verify crash-report privacy settings, capture a test event, and retain symbols and R8 mapping where applicable.
- [ ] Produce an upload-key-signed AAB, archive artifact checksums and the source commit, and install the corresponding release through a Play test track. Back up signing material securely.
- [ ] Add a small native device integration suite for login → gym setup → add member → renewal/payment → member sign-in → workout save/reopen. The existing SSO script concerns the older web module and does not establish native flow coverage.

Exit: required CI checks pass and a reproducible signed candidate runs on physical Android devices.

## 3. Validate staging and recovery — before real customer data

Owner: engineering/operator. Suggested effort: 3–5 working days; can overlap provider approvals.

- [ ] Deploy isolated staging with its own SQLite database, provider credentials, secrets, backup destination, and hostname. Use production mode and the documented staging test-payment switch only there.
- [ ] Keep one API instance initially: rate limits and schedulers are process-local. Do not add replicas without redesigning coordination and checking SQLite deployment assumptions.
- [ ] Run the existing smoke script against staging. Exercise real OTP delivery and resend/lockout behavior on intended channels, including provider outage and rejected-template cases.
- [ ] Exercise platform subscription/credit purchases and gym-owned fee collection separately: webhook replay, delayed/missing webhook, wrong amount, failed checkout, double payment, plan expiry/grace, upgrades/downgrades, and invoice reconciliation. Define the operator procedure for unresolved payments and refunds.
- [ ] Verify all four staff roles and member accounts across two gyms, access-code revocation, deleted/blocked members, multi-gym selection, and file/export scope through the signed app.
- [ ] Test offline workout saving, app process death, reconnect, and two devices editing the same member log. Document conflict behavior and demonstrate that completed workout data is recoverable.
- [ ] Restore an encrypted off-site backup onto a clean scratch deployment using the offline private key. Verify sign-in, member records, payments, uploaded files, and workout logs; record duration and acceptable data loss.
- [ ] Rehearse an upgrade and rollback with representative data. Migrations reject a newer schema on an older server, so rolling back the image alone may fail; rehearse matching database restoration and payment reconciliation for events received after the backup.
- [ ] Load-test the chosen VM using the expected pilot workload plus bursts: concurrent sign-ins, member search, attendance, sync, broadcasts, and webhooks. Record p95 latency, errors, disk growth, and backup impact; agree limits from this evidence.

Proposed initial service goals, to approve before pilot: API uptime 99.5% monthly; p95 normal API latency below 1 second at the measured pilot load; daily off-site recovery point no older than 24 hours; restore within 4 hours. These are targets, not measured results.

Exit: recorded device/provider results, a successful restore and rollback drill, and measured capacity sufficient for the pilot.

## 4. Prepare production operations and public release requirements

Owner: operator + business owner; engineering handles wiring.

- [ ] Provision production with HTTPS, restricted network access, persistent storage, distinct secrets, and encrypted off-site backups. Set independent `SEAL_KEY` and `ACCESS_CODE_KEY` before issuing real credentials; retain them across JWT key rotations.
- [ ] Wire external `/ready` monitoring, disk/backup-age checks, payment anomalies, delivery failures, OTP cost budgets, and application crashes to a support channel. Trigger each alert and record who responds.
- [ ] Write concise runbooks for outage, provider failure, stuck payment/message, secret rotation, data restore, and account deletion. Define how outstanding provider events are reconciled after recovery.
- [ ] Complete and publish privacy, terms, refund/cancellation, support, and deletion pages. Review actual data retention, health forms, member deletion, and minors handling with appropriate counsel; align the app, public text, and Play declarations.
- [ ] Publish corresponding source/notices and verify them from the installed build. Keep exercise media disabled unless the necessary license is established; test the unlicensed text-only experience.
- [ ] Complete Play data safety, health declaration, permission review, content rating, screenshots, and reviewer access. Provide a reliable reviewer login procedure without enabling development OTPs globally.
- [ ] Confirm current target SDK and other Play submission requirements in Play Console for the chosen release date.

Exit: a clean-device install points to production, public links work, alerts reach an operator, and backups have an independently verified recovery path.

## 5. Run a controlled pilot, then expand

Owner: product/support with engineering on call.

- [ ] Onboard 3–5 gyms manually. Walk through real member entry/import, plans, dues, renewal, a member workout, and the selected messaging flow.
- [ ] Complete required Play closed testing in parallel where applicable. Calendar time starts when eligible testers opt in continuously, not when development starts; allow separate review time.
- [ ] Monitor activation, successful sign-ins, saved workouts, renewals, reconciled payments, delivery outcomes/cost, crashes, and support cases. Use minimal identifiers and avoid collecting health answers in analytics.
- [ ] Proposed pilot exit: at least 14 days of active use; no unresolved critical security, data-loss, or payment-integrity defects; every payment discrepancy investigated; recovery and alert drills passed. Test count alone is insufficient.
- [ ] Submit for production access/review when applicable; roll out gradually after approval and recheck the same gates before expansion.

## Immediate next actions

1. Resolve the digital-subscription Play policy decision and confirm account/provider status.
2. Restore the Flutter toolchain and make CI fail when a signed release cannot be produced.
3. Build the signed candidate and deploy isolated staging.
4. Complete real-device/provider testing and an off-site restore drill.
5. Start the small pilot once those gates pass.

Planning allowance: roughly 2–3 engineering weeks to prepare a pilot if approvals and tooling are available, plus required testing, provider approvals, and store review. A public launch date should follow evidence from these gates.

## References

Existing implementation/runbooks: `docs/PRODUCTION_CHECKLIST.md`, `docs/DEPLOY.md`, `docs/RELEASE.md`, `docs/MEMBER_APP.md`, `.github/workflows/ci.yml`, `backend/src/db.js`.

Policies checked 22 October 2026:
- Google Play payments policy: https://support.google.com/googleplay/android-developer/answer/9858738?hl=en
- Payments policy explanation: https://support.google.com/googleplay/android-developer/answer/10281818?hl=en
- New personal-account testing requirements: https://support.google.com/googleplay/android-developer/answer/14151465?hl=en
