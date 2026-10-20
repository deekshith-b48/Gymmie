#!/bin/sh
# Encrypts the nightly verified backups with the PUBLIC backup key and copies only the encrypted files off this machine.
# The server never holds the private key, so a stolen bucket or a hacked VM cannot read a single backup. Run it from cron a little after
# the backup service (the compose file takes one every 24 h), for example:
#   30 3 * * *  cd /opt/gymmie/deploy && ./offsite-backup.sh >> offsite.log 2>&1
# Needs: rclone with a remote configured (`rclone config`, any S3-compatible bucket) and deploy/keys/backup-public.pem.
#   RCLONE_REMOTE=gymmie:gymmie-backups   (set in .env or the environment)
set -eu
cd "$(dirname "$0")"
[ -f .env ] && set -a && . ./.env && set +a
: "${RCLONE_REMOTE:?set RCLONE_REMOTE, for example gymmie:gymmie-backups}"
PUB="${BACKUP_PUBLIC_KEY_FILE:-keys/backup-public.pem}"
[ -f "$PUB" ] || { echo "no public key at $PUB: refusing to upload unencrypted backups (see docs/DEPLOY.md, Encrypted off-site backups)"; exit 1; }
mkdir -p backups/enc
count=0
for f in backups/gymmie-*.sqlite; do
  [ -e "$f" ] || continue
  out="backups/enc/$(basename "$f").enc"
  [ -f "$out" ] && continue
  docker compose run --rm -T --user "$(id -u):$(id -g)" -e BACKUP_PUBLIC_KEY_FILE=/keys/backup-public.pem \
    -v "$PWD/backups:/backups" -v "$PWD/$(dirname "$PUB"):/keys:ro" backend \
    node scripts/backup-crypt.js encrypt "/backups/$(basename "$f")" "/backups/enc/$(basename "$f").enc"
  count=$((count + 1))
done
latest=$(ls -1t backups/enc/*.enc 2>/dev/null | head -1 || true)
[ -n "$latest" ] || { echo "no encrypted backup to upload"; exit 1; }
# only encrypted files are ever sent
rclone copy backups/enc "$RCLONE_REMOTE" --include 'gymmie-*.sqlite.enc' --immutable
# keep 30 days remotely and 14 locally
rclone delete "$RCLONE_REMOTE" --min-age 30d --include 'gymmie-*.sqlite.enc'
find backups/enc -name '*.enc' -mtime +14 -delete
echo "$(date -u +%FT%TZ) offsite ok: $(basename "$latest") (new this run: $count)"
