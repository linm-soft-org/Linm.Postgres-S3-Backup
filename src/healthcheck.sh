#! /bin/sh

set -eu

if [ -z "${SCHEDULE:-}" ]; then
  exit 0
fi

if [ ! -f /tmp/last_backup_success ]; then
  echo "No successful backup recorded yet." >&2
  exit 1
fi

last=$(cat /tmp/last_backup_success)
now=$(date +%s)
max_age=$((86400 * 8))

if [ -n "${BACKUP_KEEP_DAYS:-}" ]; then
  max_age=$((86400 * (BACKUP_KEEP_DAYS + 1)))
fi

if [ $((now - last)) -ge "$max_age" ]; then
  echo "Last successful backup is too old." >&2
  exit 1
fi

exit 0
