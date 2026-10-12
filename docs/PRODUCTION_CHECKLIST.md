# Production checklist

Tick these in order. Items marked **you** need an account, a payment or a decision that only the owner can make; the rest
are done in the repository or are one command.

## A. Accounts (start first, they have lead time)

- [ ] **you** Razorpay live account (KYC), live key id/secret, webhook `https://<DOMAIN>/v5/payments/webhooks/razorpay`, event `payment_link.paid`
- [ ] **you** MSG91 with DLT-registered entity, header and two templates (OTP, and one variable)
- [ ] **you** WhatsApp Cloud API: business verified, an authentication template and a one-variable utility template approved
- [ ] **you** Resend (or another sender) with your domain verified
- [ ] **you** Domain with an A record to the server; GSTIN and legal name for invoices
- [ ] **you** Google Play developer account ($25, identity check)

## B. Server

- [ ] VM (1 vCPU / 2 GB), Docker + Compose, firewall allows 22, 80, 443 only
- [ ] `cd deploy && cp .env.example .env`, fill every value (`JWT_SECRET`: `openssl rand -hex 32`)
- [ ] `docker compose --env-file .env up -d --build`
- [ ] `node backend/scripts/smoke.js https://<DOMAIN>` passes (from your computer; add `SMOKE_PHONE=+91...` once to prove a real code arrives)
- [ ] Only ONE backend instance runs (rate limits and schedulers are in the process)
- [ ] Unattended security updates on the VM

## C. Data safety

- [ ] `rclone config` a bucket, set `RCLONE_REMOTE`, cron `deploy/offsite-backup.sh` daily
- [ ] **Restore drill done once:** `docker compose run --rm backend node scripts/restore-check.js /backups/<file>`, then restore onto a scratch VM and sign in
- [ ] Cron `deploy/healthcheck.sh` every 5 minutes with `ALERT_WEBHOOK_URL` set (down, disk, stale backup)
- [ ] External uptime monitor on `https://<DOMAIN>/ready`
- [ ] VM disk snapshots enabled

## D. Money path (Razorpay TEST keys first, then one live purchase)

- [ ] Buy a plan: subscription extends once even if the webhook is delivered twice
- [ ] Buy a credit pack: credits arrive once
- [ ] A lapsed trial: read-only for 7 days, then billing only
- [ ] A gym connects its own Razorpay keys and collects a member's due
- [ ] A GST invoice for your own sale shows your GSTIN and legal name
- [ ] Prices reviewed (`docs/GO_TO_MARKET.md`; override with `PRICING_FILE`) against MSG91 and Meta per-message cost

## E. App and store

- [ ] `sh tool/make-upload-keystore.sh`; back the `.jks` and passwords up in two places
- [ ] CI secrets: `UPLOAD_KEYSTORE_B64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`, `API_BASE_URL`
- [ ] Privacy policy, terms, refund policy and account-deletion page live (`docs/legal/`), `SITE_URL` set at build time
- [ ] Build: `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define=API_BASE_URL=https://<DOMAIN> --dart-define=SITE_URL=https://<SITE>`
- [ ] Install the release on a real phone: owner flow, member flow, a test payment
- [ ] Play Console: data safety (phone, health answers, camera), content rating, privacy and deletion URLs, Play App Signing on
- [ ] Closed-testing track with the required testers and days (check the current numbers), then production
- [ ] Keep `build/symbols` for every release (crash de-obfuscation)

## F. Legal

- [ ] **you** Lawyer reviews privacy policy and terms (India DPDP Act: member health data)
- [ ] **you** Lawyer confirms the provenance question once
- [ ] `EXERCISE_MEDIA_LICENSED` stays unset unless you hold a gymvisual.com licence
- [ ] `OPENGYM_SOURCE_URL` points at your published source (AGPL §13)
- [ ] `grep -ri dgymbook .` shows only the legacy ID-card scheme

## G. Launch

- [ ] 3-5 pilot gyms onboarded by hand, 30 days free, a WhatsApp support line
- [ ] `SUPPORT_EMAIL`, `COMPANY_WHATSAPP_NUMBER`, `HELP_CENTER_URL` set to real values
- [ ] You know the three commands for the usual problems: `admin.js gyms`, `admin.js grant-plan`, `admin.js grant-credits`
- [ ] Watch `docker compose logs -f backend` daily for the first week; review revenue with `admin.js revenue <YYYY-MM>`
