# Deploying the backend

One small server runs everything: the API, the schedulers (expiry reminders, message delivery) and a nightly backup. Run **one
instance only**: rate limits and schedulers live in the process.

## 1. Prepare

- A VM (1 vCPU / 1-2 GB is enough for the first gyms), Docker and Docker Compose, a domain name pointing at it (A record).
- Accounts to get (they take time, start first): **Razorpay** (live keys + a webhook), **MSG91** with DLT-registered templates
  (an OTP template and one generic one-variable template), **WhatsApp Cloud API** with approved templates (an authentication
  template and a one-variable utility template), optionally **Resend** for email codes.

## 2. Configure

```bash
cd deploy
cp .env.example .env     # fill it in (compose reads it; without deploy/.env nothing starts)
# generate each of these ONCE with: openssl rand -hex 32   (then back them up; see "Keys" below)
#   JWT_SECRET, SEAL_KEY, ACCESS_CODE_KEY
```

**Keys.** `JWT_SECRET` signs short-lived access tokens: rotating it only makes apps refresh. `SEAL_KEY` encrypts the Razorpay keys that gyms
save, and `ACCESS_CODE_KEY` keys the hashes of member access codes. Set both **before the first gym or code exists** and never change them:
changing either makes saved gym keys unreadable or every issued member code stop working. If you leave them unset they fall back to
`JWT_SECRET` (then `JWT_SECRET` must never change either). Back all three up outside the server.

**Cost and abuse controls.** `SMS_GLOBAL_PER_HOUR` / `SMS_GLOBAL_PER_DAY` are a hard ceiling on sign-in codes for the whole service: set them to
what you can afford (an alert fires at 80%). `ALERT_WEBHOOK_URL` receives payment mismatches, repeated lockouts, budget warnings and stuck
messages. `TURNSTILE_SECRET` (Cloudflare Turnstile) makes the public portal-OTP and registration calls require a `challengeToken`; the
Android app does not send one yet, so leave it unset until the app does, and rely on the budgets until then.

Razorpay webhook: URL `https://<DOMAIN>/v5/payments/webhooks/razorpay`, event **payment_link.paid**, secret = `RAZORPAY_WEBHOOK_SECRET`.
Production refuses to start with `DEV_*` switches, without `JWT_SECRET`, or with Razorpay keys but no webhook secret.

## 2b. Staging first (do this before production)

Run the same stack on a second small VM and a throw-away domain, with Razorpay **test** keys and your own phone number. In production mode the
server rejects a gym's `rzp_test_` keys; on staging only, set `ALLOW_TEST_PAYMENT_KEYS=1` so the gym fee-collection flow can be tried without real
money. Never set it on production. Staging still needs real MSG91 / WhatsApp credentials to receive real codes, so use your own number only.

**Staging rules (the switch is dangerous on production, so these are enforced in code where possible).**
- `ALLOW_TEST_PAYMENT_KEYS=1` is for the staging server only and is **off by default**. With it on, the server takes `rzp_test_` gym keys and
  **refuses `rzp_live_` ones**; with it off (production) it does the opposite. It also refuses to start if `RAZORPAY_KEY_ID` is a live key, or if the
  database already holds a gym's live payment account (that is production data).
- Staging must have its **own** `JWT_SECRET`, `SEAL_KEY`, `ACCESS_CODE_KEY`, database volume, domain and Razorpay **test** account. With different
  secrets a production token, sealed gym key or webhook signature is useless on staging (tested), and the reverse.
- **Never restore a production backup into staging** (it holds real people's data). Make test gyms on staging by hand or with `node src/seed.js --reset`
  against a throw-away `DB_FILE` (the seed refuses production and any database with real accounts).

## 3. Run

```bash
docker compose --env-file .env up -d --build
curl https://<DOMAIN>/ready        # {"data":{"status":"ready",...}}
```

The first start migrates the database and keeps a copy first (`<db>.pre-v<N>.bak`, not encrypted: delete it after you have confirmed the upgrade).
Check it from your computer: `node backend/scripts/smoke.js https://<DOMAIN>`. Port 8787 must not be reachable from outside (compose only exposes it to Caddy).

Caddy gets the HTTPS certificate by itself. Logs are one JSON line per request (`docker compose logs -f backend`); the query string is never logged.

## 4. Backups (encrypted off-site, and do the restore drill once, today)

The `backup` service writes a verified copy of the database to `deploy/backups/` every night and keeps the newest 14. Those files hold phone
numbers, birth dates and health answers **in clear**, so they must never leave the machine unencrypted. `deploy/offsite-backup.sh` encrypts
each one with a **public** key and uploads only the encrypted `.enc` files; it refuses to run without the key.

### Key management (read this once, carefully)

The scheme is public-key: the server holds only the public key, so a stolen bucket or a hacked server cannot read any backup. Whoever holds the
**private key and its passphrase** can read all of them, and **if you lose them the encrypted backups are unrecoverable**.

1. On **your own computer** (not the server): `BACKUP_KEY_PASSPHRASE='<a long passphrase>' node backend/scripts/backup-crypt.js genkeypair ./gymmie-backup-key`
   writes `backup-private.pem` (itself passphrase-protected) and `backup-public.pem`, and prints a fingerprint.
2. Copy **only** `backup-public.pem` to the server as `deploy/keys/backup-public.pem`.
3. Store `backup-private.pem` in **two** offline places (a password manager's file vault and a USB stick in a safe). Store the passphrase and the
   fingerprint **separately** from the key file (for example on paper). Never put either on the server, in the bucket, in git, or in chat.
4. Rotating: generate a new pair, install the new public key. Old backups still need the old private key, so keep it until they expire (30 days).
5. A second person (co-founder, lawyer, trusted family member) should know where the offline copy is. If only you know and you are unavailable, the
   business cannot recover.

### Restore drill (prove recovery works before you need it)

```bash
# on your computer, with the private key: fetch one encrypted backup from the bucket, then
BACKUP_PRIVATE_KEY_FILE=./backup-private.pem BACKUP_KEY_PASSPHRASE='...' \
  node backend/scripts/backup-crypt.js decrypt gymmie-<stamp>.sqlite.enc restored.sqlite      # refuses a wrong key or a tampered file
node backend/scripts/restore-check.js restored.sqlite                                          # integrity ok, counts look right
# to restore for real: stop the stack, copy the file to the data volume as gymmie.sqlite, start again
```

`backup-crypt.js verify <file>` checks that a backup decrypts and authenticates without writing anything. Do the drill after the first upload and
then every quarter; write down the date.

A copy of the database is also taken automatically before any schema upgrade (`<db>.pre-v<N>.bak`; it is **not** encrypted: delete it once the
upgrade is confirmed, and use full-disk encryption on the VM).

Off-site copy and alerts are two scripts you run from cron (set `RCLONE_REMOTE` and `ALERT_WEBHOOK_URL` in `.env`):

```bash
30 3 * * *   cd /opt/gymmie/deploy && ./offsite-backup.sh >> offsite.log 2>&1
*/5 * * * *  cd /opt/gymmie/deploy && ./healthcheck.sh      # down, disk filling, or no fresh backup
```

After the first deploy, prove the edges are closed from your own computer:

```bash
node backend/scripts/smoke.js https://<DOMAIN>
```

The full launch list is [PRODUCTION_CHECKLIST.md](PRODUCTION_CHECKLIST.md).

## 5. Operating it

```bash
docker compose exec backend node scripts/admin.js gyms
docker compose exec backend node scripts/admin.js revenue 2026-11
docker compose exec backend node scripts/admin.js grant-plan 123456 GROWTH 30     # a gym code, free month
docker compose exec backend node scripts/admin.js grant-credits 123456 500
docker compose exec backend node scripts/admin.js delete-gym 123456 123456         # support request to close a gym
docker compose exec backend node scripts/admin.js events 50                        # lockouts, SMS budget, payment mismatches (newest first)
docker compose exec backend node scripts/admin.js mismatches                       # money arrived but the amount did not match: nothing was delivered
docker compose exec backend node scripts/admin.js order-apply 123456 <orderId>     # after checking Razorpay: deliver it, once
docker compose exec backend node scripts/admin.js order-dismiss 123456 <orderId> refunded pay_ABC123
docker compose exec backend node scripts/admin.js recover-messages                 # messages stuck in "sending": failed and refunded once, never re-sent
```

A person who is locked out after five wrong codes waits 15 minutes (then 30, 60 ... up to 4 hours); the lock lifts by itself and a correct sign-in
clears it. Nothing is sent to a locked number and the app cannot tell the difference, so tell a locked-out owner to wait rather than ask for more codes.

Prices live in `backend/src/domain/catalog.js`; put a JSON file at `PRICING_FILE` to change them without a code change.

## 5b. Environment reference

Set by `docker-compose.yml` (do not put these in `.env`): `NODE_ENV=production`, `DB_FILE=/data/gymmie.sqlite`, `TRUST_PROXY=1`, `HOST`/`PORT`
(0.0.0.0 / 8787), `BACKUP_DIR`, `KEEP`. Everything you may set is in `deploy/.env.example`. Optional extras (defaults are fine for a first launch):

| Variable | Meaning | Default |
|---|---|---|
| `MINIMUM_APP_VERSION`, `MINIMUM_SUGGESTED_APP_VERSION` | Versions below the first are forced to update, below the second are nudged | `1.0.0`, `1.9.0` |
| `MAINTENANCE_MODE` | `1` shows the maintenance screen in the app | off |
| `ACCESS_TTL_SEC`, `REFRESH_TTL_SEC` | Access token life (15 min) and sign-in life (30 days) | 900, 2592000 |
| `LOG_REQUESTS` | One JSON log line per request | on |
| `WHATSAPP_API_VERSION`, `WHATSAPP_LANGUAGE` | WhatsApp Cloud API version and template language | `v20.0`, `en` |
| `SELF_REGISTRATION_PLATFORM`, `SIGN_UP_CONTACT_NUMBER` | Values the app shows on sign-up | empty |
| `BACKUP_PUBLIC_KEY_FILE` | Public key used by `scripts/backup-crypt.js encrypt` (set by `offsite-backup.sh`) | none |

**Never set in production:** `DEV_EXPOSE_OTP`, `DEV_FIXED_OTP`, `DEV_PAYMENTS` (the server refuses to start), and `RATE_LIMIT_SCALE` (a value above 1
silently loosens every rate limit and SMS budget; it exists for the test suite). `SMOKE_PHONE` is only for `scripts/smoke.js` on your own computer.

## 5c. Rolling back an upgrade

Every upgrade that changes the database first writes a copy next to it: `/data/gymmie.sqlite.pre-v<N>.bak` (N = the schema version you came from). The new server
refuses to open a database newer than itself, so rolling back **code alone fails by design**; roll back both. The file-level behaviour (the `.bak` is
created, the old code refuses the new database, the old code opens the restored copy) was tested locally; the `docker compose` commands below were **not** run
against a container runtime yet, so rehearse them on staging first:

```bash
cd deploy
docker compose --env-file .env stop backend backup
git checkout <previous tag>                                   # the code you were running before
docker compose --env-file .env run --rm --no-deps backend sh -c \
  'rm -f /data/gymmie.sqlite-wal /data/gymmie.sqlite-shm && cp /data/gymmie.sqlite.pre-v<N>.bak /data/gymmie.sqlite'
docker compose --env-file .env up -d --build
curl https://<DOMAIN>/ready && node ../backend/scripts/smoke.js https://<DOMAIN>
```

Restoring the copy **loses everything written since the upgrade** (new members, payments). If that matters, restore from the encrypted off-site backup instead
(section 4) or fix forward. Decide quickly: the longer the new version runs, the more data a rollback discards. Delete the `.pre-v<N>.bak` once you are sure
you will not roll back (it is not encrypted).

## 6. Monitor

- An uptime check (any free service) on `https://<DOMAIN>/ready`, alerting to your phone.
- Disk space of the data volume (SQLite grows with photos; move images out of the database when it passes a few GB).
- Razorpay dashboard: failed webhooks.

## Updating

```bash
git pull && docker compose --env-file .env up -d --build
```

The server stops cleanly on SIGTERM (finishes requests, folds the write-ahead log into the database).
