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
cp .env.example .env     # fill it in; JWT_SECRET: openssl rand -hex 32
```

Razorpay webhook: URL `https://<DOMAIN>/v5/payments/webhooks/razorpay`, event **payment_link.paid**, secret = `RAZORPAY_WEBHOOK_SECRET`.
Production refuses to start with `DEV_*` switches, without `JWT_SECRET`, or with Razorpay keys but no webhook secret.

## 3. Run

```bash
docker compose --env-file .env up -d --build
curl https://<DOMAIN>/ready        # {"data":{"status":"ready",...}}
```

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
```

Prices live in `backend/src/domain/catalog.js`; put a JSON file at `PRICING_FILE` to change them without a code change.

## 6. Monitor

- An uptime check (any free service) on `https://<DOMAIN>/ready`, alerting to your phone.
- Disk space of the data volume (SQLite grows with photos; move images out of the database when it passes a few GB).
- Razorpay dashboard: failed webhooks.

## Updating

```bash
git pull && docker compose --env-file .env up -d --build
```

The server stops cleanly on SIGTERM (finishes requests, folds the write-ahead log into the database).
