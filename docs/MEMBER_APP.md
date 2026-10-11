# Member app (gym members)

Gym members get their own sign-in on the login page and a **native Flutter app** that ports openGym's
training log: Home, Plan, a live workout with rest timer, History, Stats, the exercise library with
GymMane's **Choose a focus** body map, and **My gym** (membership, expiry, trainer, check-in QR) inside Home, with a gym profile and gym stats. Staff flows
are untouched. There is no WebView: the training logic is Dart, checked against openGym's own JavaScript.

## What is ported (Phase 1) and what is not yet

| Area | Status |
|---|---|
| Home (week strip, today's routine, body weight, streak, **My gym** section: membership, check-in code, profile, trainer plan) | done |
| Gym profile (membership and payment, the gym's plans, gym details, trainer) and Stats "Your gym" (visits, streak, per-week bars) | done |
| Trainer-assigned workout plan: view and start a day as a session | done |
| Plan: routines, exercises with sets/reps/weight, weekday schedule | done |
| Start: today's plan, other routines, freestyle, **Choose a focus** (body map, pick exercises) | done |
| Live workout: tick sets (timestamped), weight/reps steppers, add/remove sets and exercises, notes, rest timer (+15 s, skip), finish / discard, records (heaviest weight and estimated 1RM) | done |
| History (list, detail, delete), Stats (weekly volume, estimated 1RM per exercise and curve) | done |
| Library: 5,632 exercises with pictures, search, muscle and equipment filters, favourites, detail | done |
| Local-first storage and sync with the Gymmie backend (offline edits, merge on conflict, delete-everything) | done |
| **Stats → Activity (last 12 months)**: openGym's heatmap (Time / Volume, 53 weeks, five shades, tap a day to open its workout), plus its four tiles | done |
| **Settings** (see below): workout, timer alerts, plan, units, equipment, look, data, about, account | done |
| Automatic progression policies (linear, double, greyskull, triple), warm-up ramps, supersets, drop sets and rest-pause, dumbbell "each/total", plates and bar maths | **not yet** (rows start from last time or the plan) |
| Measurements, progress photos, day notes, rotation/queue, AI coach, backup folder, push reminders, Hevy/FitNotes/Strong imports, languages beyond English | **not yet** |
| Custom exercises: read and use; creating them in the app | **not yet** |

The data document keeps openGym's JSON shape and preserves keys the app does not understand, so a log is not damaged by a
round trip and the missing features can be added later.

## Architecture

```
 Login page "For gym members" ──▶ POST /v5/member/auth/otp, /verify ──▶ member session (own token type, tables, router mode)
 AppRoot ──▶ MemberSessionCubit.signedIn ? NativeMemberApp : GymmieApp (staff)   (two separate MaterialApps)
 NativeMemberApp ──▶ MemberLogStore (phone, shared_preferences) ◀──sync──▶ GET/PUT /v5/member/data (one JSON document per member, revisioned)
```

- `lib/features/member/native/domain/`: pure Dart, no Flutter. `onerm.dart`, `rows.dart`, `history.dart`, `finish.dart`,
  `session.dart`, `plan.dart`, `merge.dart`, `catalogue.dart`.
- `lib/features/member/native/log_store.dart`: the local-first store and sync loop. `ui/`: screens in openGym's dark look.
- `assets/member/exercises.json` and `body.json` are exported from openGym by `member-app/scripts/export-catalogue.mjs`
  (muscle weights, cardio and assisted flags are computed by openGym's own code). Pictures come from the training-log host
  (`mediaBase`, openGym's `web` container serves `exercise-media/`), not from the APK.
- Backend: `backend/src/{member_auth.js,routes/member_app.js}`; migrations v2 (member sessions) and v3 (`member_state`).

## Data model

- **Log document** (`member_state`, one row per member): openGym's state shape (`workouts`, `routines`, `week`, `bodyweight`,
  `exWeights`, `customEx`, `favEx`, `unit`, `restSec`, ...). Max 2 MB. `rev` increments on every save; `PUT` with a stale `baseRev`
  answers 409 with the current document. An unfinished workout (`active`) never leaves the phone.
- **Merge** (two devices changed): workouts, weigh-ins and measurements are unioned (nothing logged is lost); routines and custom
  exercises are unioned by id with this phone winning a clash; best-known weights keep the heavier one. Limit: without tombstones a
  routine deleted on one device returns if another device still has it.
- **Member session**: `member_sessions` table, token claim `typ:'member'`, rotating refresh with reuse detection.

## API

| Endpoint | Purpose |
|---|---|
| `POST /v5/member/auth/otp` / `otp/verify` / `select-gym` / `refresh` / `logout` | phone + OTP sign-in (same answer for non-members), multi-gym pick |
| `GET /v5/member/me` | whitelisted profile, membership, trainer, visits, QR payload, `mediaBase` |
| `GET /v5/member/me/profile` | member, gym details, trainer, membership history with payment and the plan's `benefits`, the gym's active plans |
| `GET /v5/member/me/attendance?days=` | visits, total, last 30 days, streak, last visit |
| `GET /v5/member/me/plans` | the workout / diet the gym assigned (null when the feature is off) |
| `GET` / `PUT /v5/member/me/preferences` | the member's own choice about promotional broadcasts (`broadcasts`); the owner sees it |
| `POST /v5/member/auth/logout-all` | "Sign out everywhere": ends every session of this member on every phone |
| `GET` / `PUT` / `DELETE /v5/member/data` | the training log (revisioned; delete = "erase my data") |
| `POST /v5/member/opengym/launch`, openGym `/api/sso/*` | optional web access to the same openGym server (not used by the app) |

## Authentication and authorization

- Every `auth:'member'` request re-checks: session not revoked, member exists and is not blocked, phone unchanged, gym has `MEMBER_APP` on.
- The member id comes from the session row only; responses are field whitelists. A route sweep test proves member tokens are refused on
  every staff route and staff tokens on every member route.
- Blocking, deleting or re-numbering a member ends their sessions at once and removes their data on delete.
- The training log is private to the member: no staff route reads `member_state`.

## Migration

Back up the SQLite file, start the new backend (v2 and v3 apply in one transaction each; an older binary still runs on the file), set
`OPENGYM_PUBLIC_URL` to the host that serves exercise pictures, switch **Member App** on for a pilot gym.

## Deployment checklist

- [ ] `NODE_ENV=production`, real `JWT_SECRET`, HTTPS, restricted CORS; a **real OTP provider** (production has none; member login needs it).
- [ ] Exercise pictures hosted: build `member-app/` (openGym `web` image) or any static host with `exercise-media/still/*.webp`; set `OPENGYM_PUBLIC_URL`.
- [ ] Release signing key, version code bump, `--dart-define=API_BASE_URL=https://...`.
- [ ] Privacy policy and store data-safety form (phone number and fitness data are processed).
- [ ] AGPL: publish `member-app/opengym/` source and pass `--dart-define=OPENGYM_SOURCE_URL=...`; the Dart port derives from openGym and GymMane.
- [ ] Backups of the SQLite file (`.sqlite`, `-wal`, `-shm` together); single backend instance.

## Testing

| Level | Where |
|---|---|
| Golden (Dart vs openGym's JS) | `test/member/domain_test.dart`: 2,880 1RM cases, best sets/weights, session end, finished workouts, volume, history, records. `test/member/settings_golden_test.dart`: accent colour maths on both themes, whole-log kg ⇄ lb conversion, the Activity heatmap grid and shades (both week starts, both metrics), effort stepping, equipment profiles. Fixtures: `node member-app/scripts/gen-fixtures.mjs` |
| Unit | `test/member/native_test.dart`: session building/editing/finishing, merge, sync store (offline, restart, conflict, race, erase) |
| Widget | `test/member/native_ui_test.dart`: Choose a focus (real body-map tap), workout (tick, rest, finish, discard), home, library, shell on a small phone. `test/member/settings_ui_test.dart` (44): every Settings page and what each setting does to Home, Start (weigh-in), the workout (effort, collapse, buttons, pictures, rest off), the library, theme and accent, the Activity card, backups |
| Backend | `backend/test/member_app.test.js` (26): sign-in, isolation sweep, migration, data document, cut-off on block/delete/phone change |
| Emulator | login, member OTP, Home, Choose a focus (chest), pick two exercises, start, step weight, tick (rest timer), finish, row stored on the server |

## Rollback

Switch `MEMBER_APP` off per gym; ship a build without the section; redeploy the previous backend (schema additive); restore the DB copy;
restore `Gymmie.baseline-*.tar.gz`. Local logs stay on the phone under their own key.

## Role descriptor (shown in the app)

> **Gym member.** You are a customer of your gym, not staff. Sign in with the phone number your gym has on file. Log workouts with
> rest timers, pick what to train from the body map, and see your records and progress. *My gym* shows your plan, expiry date, balance and
> trainer, and a QR code the front desk scans to check you in. Your training log is yours; your gym's staff cannot read it. Payments,
> renewals and plan changes are handled by the front desk. Trainers, staff, managers and owners use the staff login.

## Settings

Every setting is a key in the member's log document, with openGym's own name and default (`lib/features/member/native/domain/settings.dart`).
So a setting is saved on the phone at once, follows the member to the account and to their other phones through the normal sync, survives a
restart, and travels in an openGym backup. A phone that never set one cannot overwrite the account's choice when two copies merge.

| Page | What it does |
|---|---|
| Workout | rest timer (off at 0:00); effort per set (RIR / RPE, a line under each set); "shown under each exercise" (last time / best set); collapse completed exercises; weigh in before workouts; keep screen awake; exercise pictures (full / small / hidden); fine-tuning: planned sessions start from (plan / last session), weight and reps buttons |
| Timer alerts | sound, vibration, screen flash when a rest ends |
| Plan & schedule | week starts on Monday / Sunday; load a starter plan (push/pull/legs, upper/lower, full body, 5×5) |
| Units | kg / lb (convert every stored weight, or keep the numbers and change the label; a later switch on one phone is followed by the others); weight decimals; the 1RM formula |
| Equipment | profiles ("Home", "Gym"…) that filter the library, the picker and "Choose a focus" |
| Look & Home | dark / light / system theme and an accent (presets or your own colour, kept readable) that repaint the app at once; body diagram; show or hide the check-in button, the body-weight card and the connection banner |
| Data & backup | export the log as openGym's JSON; import a backup (it is added to the log, nothing is deleted); delete all my training data |
| My account | profile; **Messages from my gym**; sync status; sign out; sign out everywhere |

**What the owner sees.** The one setting that concerns the gym is "Messages from my gym". It is stored on the member's own record at the gym
(`communication.broadcasts`, writable only by the member through `PUT /v5/member/me/preferences`). The owner sees it on the member's page
(`memberApp.broadcasts`), broadcasts skip members who turned it off, and the recipient preview says how many were left out (`optedOut`).
Notices about the membership itself (renewal, balance, receipts) are not affected. Everything else is the member's private training log: no
staff route reads it.

**Safety.** `PUT /v5/member/data` checks the type and range of every setting it knows (a wrong type is a 422) and keeps every key it does not.

**Not ported from openGym Settings** (the feature does not exist in the member app): reminders and push notifications, the AI coach,
languages and translated exercise names, choosing among the six rest sounds, the Cards / List / Compact / Focus workout layouts, rotation
scheduling, plates and dumbbell inventories, Health Connect, auto-backup folder, passkeys and device pairing (replaced by the gym sign-in),
and the self-hosting rows (the account lives on the gym's server).

## Owner and member relationship

- Staff see on a member's page whether the app is on and when the member last used it (`memberApp` in `GET /v5/members/:id`).
- Block, delete or change the phone number: the member's sessions end on the next request and, on delete, their log is erased.
- The member reads membership, balance, visits, the trainer's plans and the gym's plans live from the server; the screens keep the
  last answer so they open offline. Training logs stay private to the member.
- Gymmie's default exercise library includes openGym's 5,632 exercises (`og:<id>`), so a trainer's plan can name the same exercises the member logs;
  starting a plan day matches by id, else by name.

## Member access codes and the welcome

Registering a member (`POST /v5/members`) issues a code for that gym, shaped `<gym code>-XXXX-XXXX` (32 unambiguous characters, 8 random ones). The code is in that
answer only and is shown with copy/share; the server keeps just an HMAC. From the member's page the gym can issue a new code (the old one dies at once and the
member is signed out everywhere) or revoke it (`POST|DELETE /v5/members/:id/access-code`). The member opens **Member login** from the login page and enters the code
(`POST /v5/member/auth/code`): the server finds the gym from the prefix and the member from the hash, answers every failure the same way, rate-limits by address,
by gym and by gym+address, and refuses blocked members and gyms with the member app off. After a fresh sign-in the app shows "Welcome to <gym>!" for about three seconds,
then Home, whose **My membership** card shows the plan, status, start and expiry, the month, visits this month, price paid and balance, payment status ("Pay online"
when the gym has connected its own payment account) and renewal ("Request renewal" near the end).

## Signing in

There is one login page. Everyone enters a phone number and gets one code (`POST /v5/auth/signin/otp`, then `/verify`). After the code the server
decides: staff only -> staff session; one member record -> member session; staff and member, or members in several gyms -> `status: choose` with a signed
selection token, and the app asks "Continue as" (`POST /v5/auth/signin/choose`). The earlier `/v5/member/auth/*` and `/v5/auth/login/*` routes still work
(email sign-in for staff uses the latter). Roles are re-judged when the code is used, so a member blocked in between gets nothing.

## Account, privacy and permissions

Everything here is a `/v5/member/me/*` route (`auth:'member'`). The member's id, gym and role come from the token on every request and are
never read from the body or URL; another member's id or session answers "not found", never "forbidden" (no IDOR, no existence leak).

| Area | What the member can do | What only the gym can do |
|---|---|---|
| Account & profile | Edit name, email, gender, birth date, blood group, address, emergency contact, height, weight, fitness goal/level/days/notes; photo; change phone number (code sent to the new number, other phones signed out) | Plan, dates, payment status, benefits, pricing, status, trainer |
| Membership | See plan, status, dates, benefits, balance, payments and invoices; **request** renew / change plan / cancel (one pending per kind; withdraw any time) | Owner and managers approve or reject (`requests.write`); front desk can read (`requests.read`). A decision records the answer only; the membership and the money are changed by staff as usual |
| Privacy | Choose whether their trainer sees email, birth date, address, emergency contact, health data; share a training summary with nobody / trainer / gym staff | Owner and managers always see what they need to run the membership |
| Notifications | Switch gym messages and the expiry reminder (1-30 days before) | Receipts, renewals and security notices are mandatory and listed, not switchable |
| Security | Devices list, sign out one / all others / everywhere. There is no password: sign-in is a code to the phone | |
| Delete account | Code + typing DELETE. Erases the training log, photo, contact and fitness details and preferences; signs out everywhere; blocks app sign-in | The gym keeps name, phone, memberships, payments, attendance and health records it entered, and can reopen the app account (`POST /v5/members/:id/member-app/reopen`) |
| Workout reminder | Setting in the log (`reminder {on,time}`) fires on days that have a routine, skipped when already trained today; scheduled on the phone (Kotlin `AlarmManager`, survives reboot) | |

Staff side: `GET /v5/membership-requests`, `POST /v5/membership-requests/:id/decision`, `GET /v5/members/:id/training` (only what the member shares),
`POST /v5/members/:id/app-invite`. Trainers only see members assigned to them and, in those, only the fields the member lets them see
(memberships and PAR-Q submissions are scoped the same way). Platform-wide settings stay admin-only; gym settings stay owner/staff; members only read what
applies to them (gym name, plans, currency, which features are on).

Membership-expiry alerts are sent by a scheduler (every 15 minutes) once per membership, on the member's own schedule, never to a member who opted out.
Delivery goes through the gym's messaging (WhatsApp/SMS); the development backend records messages in an outbox instead of sending them.

## Known gaps

- Everything marked "not yet" above. Notably: no automatic progression, no warm-up ramp, no supersets.
- Exercise names are English only; the web app's translations are not ported.
- No iOS/watch support; Android only (as the rest of Gymmie).
- The workout-day reminder is a local Android notification (needs the notification permission); there is no server push.
- Not ported from openGym's settings: language, rest sounds picker, workout layouts, rotation, plates and dumbbell inventories, Hevy/other-app imports, auto-backup, AI coach, in-app updates, passkeys.
- The Docker compose file for `member-app/` is untested (Docker is not installed on the build machine).
