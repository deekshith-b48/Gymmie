# Gymmie 1.0

First public release. A Flutter gym-management app for owners, managers, staff and trainers, plus a development backend you
can run locally. Built on the reconstruction of DGymBook Partner 1.9.4 (in-app version `1.9.4+1178`, application id
`com.dgymbook.app`, unchanged so existing installs and QR codes keep working).

> The backend is a **development** service, not the original DGymBook production system. OTP delivery, payments and
> WhatsApp are stand-ins and nothing is sent. See "Provenance" in the README.

## What's in 1.0

**Run a gym**
- Members: search, filters, add or edit, detail tabs, renew, upcoming memberships, upgrade, freeze, extend, end, block, labels, trainer assignment
- Membership plans, plan groups and session-based plans with a live server-side price quote (discount, tax included or excluded, partial payments)
- Transactions, balances, settle dues, balance reminders, invoice PDF, expenses, products and sales
- Leads: pipeline, snooze, convert to a member
- Staff and roles, trainer schedule, working hours and session bookings

**Look after members**
- Workout and diet plan templates, an exercise library, rule-based plan generators, assign plans to members
- PAR-Q health forms: builder with major and minor versions, generator by screening area, signing with a signature pad, risk flags
- **Member ID cards**: photo, plan validity, labels, a check-in QR, three colour themes, share as an image

**Stay in touch**
- Broadcasts, message templates, credits, history, feedback inbox, video links, gym poster

**Admin control**
- Attendance, the live "Members in gym" card and Biometric devices are **off by default**; switch them on under
  *Settings → App Features → Attendance & Access*
- Roles: owner, manager, staff, trainer, enforced on the server with per-gym tenant isolation

**Quality**
- `flutter analyze` clean; 20 Flutter tests and 38 backend end-to-end tests pass
- A membership price quote now reports a start-date overlap straight away instead of when you confirm

## Install

| File | Use |
|---|---|
| `gymmie-1.0-debug-usb.apk` | Phone or emulator; backend reached through `adb reverse tcp:8787 tcp:8787` |
| `gymmie-1.0-release-arm64.apk` | Phone against an HTTPS backend (set it in Developer tools) |

Both are arm64 builds, minimum Android 7.0 (API 24). The release APK is signed with the **debug key** because no release
keystore is bundled; it is meant for sideloading and testing, not the Play Store. Steps are in the README ("Install on a phone").

## Known gaps

Report-schedule settings page, `dgymbook://payments` deep-link handler, push-notification registration (needs a real
Firebase project), `view-photo` route, full Hindi localisation, and an end-to-end device run of the PAR-Q signing flow.
Full status: `docs/FEATURE_MATRIX.md`.
