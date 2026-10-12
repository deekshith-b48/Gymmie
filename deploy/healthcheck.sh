#!/bin/sh
# Cron-able watchdog. Tells you (webhook, or just the exit code and output) when the server is down, the disk is
# filling, or the nightly backup is missing. Run every 5 minutes:
#   */5 * * * *  cd /opt/gymmie/deploy && ./healthcheck.sh
# Set ALERT_WEBHOOK_URL in .env to a Slack/Discord/ntfy URL that accepts a JSON {"text": "..."} POST (ntfy: plain body works too).
set -u
cd "$(dirname "$0")"
[ -f .env ] && set -a && . ./.env && set +a
problems=""
add() { problems="$problems\n- $1"; }

code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://${DOMAIN:?DOMAIN not set}/ready" || true)
[ "$code" = "200" ] || add "https://$DOMAIN/ready answered $code"

used=$(df -P . | awk 'NR==2{gsub("%","",$5); print $5}')
[ "${used:-0}" -lt "${DISK_ALERT_PERCENT:-85}" ] || add "disk is ${used}% full"

newest=$(ls -1t backups/gymmie-*.sqlite 2>/dev/null | head -1 || true)
if [ -z "$newest" ]; then add "no backup file found"
else
  age=$(( $(date +%s) - $(stat -c %Y "$newest" 2>/dev/null || stat -f %m "$newest") ))
  [ "$age" -lt 129600 ] || add "newest backup is $((age / 3600)) h old"
fi

if [ -n "$problems" ]; then
  msg="Gymmie alert on $(hostname):$(printf "$problems")"
  echo "$msg"
  [ -z "${ALERT_WEBHOOK_URL:-}" ] || curl -s -m 10 -H 'content-type: application/json' -d "{\"text\": \"$(printf "$msg" | sed 's/"/\\"/g' | tr '\n' ' ')\"}" "$ALERT_WEBHOOK_URL" >/dev/null
  exit 1
fi
