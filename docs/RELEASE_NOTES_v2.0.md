# Gymmie 2.0.0

Released 2026-10-11 · version `2.0.0+2000` · application id `app.gymmie.android`

Gymmie 2.0 is the first version that can take a paying gym: a native member app, real billing and message delivery, one look
across both apps, and a clean identity. It is a **new app** (new application id), not an update of 1.x.

## Highlights

- **Member app**: native, offline-first training log ported from openGym, plus *My gym* (membership, expiry, balance, renewal, check-in QR).
- **One sign-in** for owners, staff and members, and **access codes** that a gym issues, re-issues or revokes.
- **Launch flow**: animated logo, optional walkthrough, **14-day free trial**, optional online fee collection.
- **Billing**: Starter, Growth and Pro enforced on the server, Razorpay payment links with signed idempotent webhooks, GST invoices, referral rewards, credit packs.
- **Gyms collect their own fees** through their own Razorpay account.
- **Real delivery** by SMS (MSG91), WhatsApp (Cloud API) and email (Resend); failed messages return their credit.
- **Exercise animations** in both apps (needs a licence for the media, see NOTICE.md).
- **One look** for owner and member apps; new logo and launcher icon.
- **Operations**: Docker, Caddy HTTPS, nightly verified backups, `/ready`, graceful shutdown, JSON logs, CI, operator console.

Everything, with fixes and test counts, is in [CHANGELOG.md](../CHANGELOG.md).

## Download

| File | What it is |
|---|---|
| `gymmie-2.0.0-android-arm64.apk` | Test build for 64-bit Android 7.0+. Debug-signed, **not for the Play Store**. Asks for your backend's HTTPS address on first run. |

SHA-256 of the APK is in `gymmie-2.0.0-android-arm64.apk.sha256`.

## Upgrading and things to know

- **New application id.** 1.x installs are not replaced; install 2.0 alongside and move gyms over.
- **Backend.** Run the backend from this tag. The database migrates itself on start (a copy is taken first). See [docs/DEPLOY.md](DEPLOY.md).
- **Production refuses unsafe settings**: `JWT_SECRET` is required, `DEV_*` switches are rejected, and Razorpay keys need a webhook secret.
- **Exercise pictures** are not part of this repository. Without a licence from gymvisual.com the library works as text and body-map filters.
- **Not in 2.0**: push notifications (FCM), iOS, languages beyond English and part of Hindi. See *Known gaps* in the README.

## Verified

- `flutter analyze`: no issues. `flutter test`: 202 passing. `backend npm test`: 129 passing.
- Android 15 emulator (debug build): owner sign-in, issue an access code, member login, welcome, dashboard, membership card, exercise animation. The release build installs and starts on the same emulator.
