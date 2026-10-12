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

## 4. Backups (do the restore drill once, today)

The `backup` service writes a verified copy of the database to `deploy/backups/` every night and keeps the newest 14. Copy that folder
off the machine, for example with rclone to any S3-compatible bucket:

```bash
rclone sync deploy/backups remote:gymmie-backups
```

Restore drill (prove it works before you need it):

```bash
docker compose run --rm backend node scripts/restore-check.js /backups/<file>.sqlite   # integrity ok, counts look right
# to restore: stop the stack, copy the file to the data volume as gymmie.sqlite, start again
```

A copy of the database is also taken automatically before any schema upgrade (`<db>.pre-v<N>.bak`).

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
