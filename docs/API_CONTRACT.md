# API contract

> This is the contract between the Gymmie app and the Gymmie backend in `backend/`: conventions, request and
> response shapes, status codes and business rules, as implemented and tested by `backend/test/*.test.js`.
> The route list is generated from the router (`node backend/scripts/dump-routes.js`, see `docs/API_ROUTES.md`).
> It is the API of this repository's server only; the app is not meant to be pointed at any other service.

## Conventions

| Topic | Rule |
|---|---|
| Transport | JSON over HTTP(S). `Content-Type: application/json`. Files are uploaded as base64 JSON (≤ 5 MB decoded). |
| Success | `200/201` with `{ "data": …, "meta"?: { page, limit, total, totalPages, … } }`; `204` has no body. |
| Errors | `{ "error": { "code", "message", "details"? } }`. 400 bad request · 401 unauthenticated/expired · 403 forbidden · 404 · 409 conflict · 422 validation (`details` = field → message) · 402 `INSUFFICIENT_CREDITS` · 429 rate-limited (`Retry-After`) · 501 provider not configured. |
| Auth | `Authorization: Bearer <accessToken>` (HS256 JWT, 15 min). Refresh with `POST /v5/auth/refresh` (rotating, reuse of an old token revokes the whole session family). |
| Gym scope | Gym-scoped routes need `x-gym-id`. The server verifies the caller belongs to that gym (tenant isolation) and checks the role's permission. |
| Roles | `owner` (all), `manager`, `staff`, `trainer` (own members, plans, bookings). Matrix: `backend/src/auth.js` (mirrored in `lib/core/auth/permissions.dart`). |
| Pagination | `?page=1&limit=20` (max 200). |
| Dates | Calendar dates `YYYY-MM-DD` in the gym's timezone; instants are ISO-8601 UTC. |
| Phones | E.164. Indian numbers must match `+91[6-9]\d{9}`. |
| Money | Decimal numbers (2 dp), gym currency. Tax is a gym-level config (included / excluded). |

## Business rules implemented (and tested)

* **Pricing**: `discount ≤ price` ("Discount cannot be greater than plan price"); percent 1–100; tax *excluded* adds `rate%`, tax *included* carves it out of the price; `amountReceived ≤ total`.
* **Memberships**: start defaults to the day after the running plan ends; overlapping windows are refused (409); statuses `active · upcoming · paused · expired · ended` are derived from dates + flags; freeze/resume extends `endDate` by the paused days; extend, end, start-now, upgrade; session-based plans track per-session logs.
* **Balances**: settlement allocates oldest-first across memberships and product sales, supports split payment methods, refuses over-payment; write-off (owner/manager) clears the due; balance reminders.
* **Attendance**: manual / QR (`gymmie://member/<gymCode>/<memberId>`; older `dgymbook://` ID cards are still accepted) / biometric. Refused for blocked members, expired or frozen plans, duplicate same-day marks; biometric also refused when a balance reminder is overdue.
* **Stock**: tracked products cannot be oversold; sale deletion restores stock; receive/damage/correct are ledgered; "log as expense".
* **Messaging**: automated messages and broadcasts debit credits (1 / message); scheduled broadcasts reserve credits and refund on cancel.
* **Trainer bookings**: only inside the trainer's working hours, no overlap, within the member's remaining session budget, trainer must be assigned to the member.
* **PAR-Q**: versioned forms; *major* revision requires re-signing, *minor* does not; risk level from flagged answers.
* **Feature flags**: catalogue in `assets/feature_flags_data.json` (mirrored in `backend/src/feature_flags.json`); gating enforced server-side for health, diet, workout, AI generators, insights, quick reports.

## Clearly-labelled development stand-ins

| Area | What the dev backend does | What a production system must replace |
|---|---|---|
| OTP delivery | Logs the code; returns it as `devOtp` only when `NODE_ENV≠production` (refused in production) | SMS / WhatsApp / e-mail provider in `AuthService.createOtp` |
| Payments (credits, subscription) | `/dev/pay/:token` simulated checkout page; deep-links back with `gymmie://payments?status=…` | Real payment gateway (order creation + signed webhook) |
| WhatsApp / SMS | Writes to an outbox (`status: recorded`); credits are still debited | A messaging provider; set `status` to `sent` / `failed` |
| AI plans & insights | Deterministic rule-based generators (`generator: "rule-based-dev"`) | A hosted model |
| Biometric devices | Device callback API (`x-device-key`) + simulator script | Vendor integration |
| Credit packs / subscription plans | Small dev catalogue (flagged `catalog: "dev"`) | Real price list |
| Report e-mails / exports e-mailed | Exports are returned as CSV downloads; the report schedule is stored but not sent | Mail provider |

The full machine-generated route list is in [`API_ROUTES.md`](API_ROUTES.md).
