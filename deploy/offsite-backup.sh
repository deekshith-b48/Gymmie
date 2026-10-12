#!/bin/sh
# Copies the nightly verified backups off this machine. Run it from cron a little after the backup service
# (the compose file takes one every 24 h), for example:
#   30 3 * * *  cd /opt/gymmie/deploy && ./offsite-backup.sh >> offsite.log 2>&1
# Needs rclone with a remote configured (`rclone config`): any S3-compatible bucket (R2, B2, S3, Wasabi).
#   RCLONE_REMOTE=gymmie:gymmie-backups   (set in .env or the environment)
set -eu
cd "$(dirname "$0")"
[ -f .env ] && set -a && . ./.env && set +a
: "${RCLONE_REMOTE:?set RCLONE_REMOTE, for example gymmie:gymmie-backups}"
latest=$(ls -1t backups/gymmie-*.sqlite 2>/dev/null | head -1 || true)
[ -n "$latest" ] || { echo "no backup file in deploy/backups"; exit 1; }
rclone copy backups "$RCLONE_REMOTE" --include 'gymmie-*.sqlite' --immutable
# keep 30 days remotely
rclone delete "$RCLONE_REMOTE" --min-age 30d --include 'gymmie-*.sqlite'
echo "$(date -u +%FT%TZ) offsite ok: $(basename "$latest")"
