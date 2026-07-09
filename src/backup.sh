#! /bin/sh

set -eu
set -o pipefail

source ./env.sh
source ./s3.sh

lock_dir="/tmp/backup.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "Another backup is already in progress." >&2
  exit 1
fi
trap 'rmdir "$lock_dir"' EXIT INT TERM

echo "Creating backup of $POSTGRES_DATABASE database..."
# PGDUMP_EXTRA_OPTS intentionally unquoted to allow multiple flags
pg_dump --format=custom \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DATABASE" \
        $PGDUMP_EXTRA_OPTS \
        > db.dump

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_NAME_PREFIX}${POSTGRES_DATABASE}_${timestamp}.dump"

if [ -n "$PASSPHRASE" ]; then
  echo "Encrypting backup..."
  rm -f db.dump.gpg
  gpg --symmetric --batch --cipher-algo AES256 --passphrase "$PASSPHRASE" db.dump
  rm db.dump
  local_file="db.dump.gpg"
  s3_uri="${s3_uri_base}.gpg"
else
  local_file="db.dump"
  s3_uri="$s3_uri_base"
fi

echo "Uploading backup to $S3_BUCKET..."
aws_cmd s3 cp "$local_file" "$s3_uri"
verify_s3_upload "$s3_uri" "$local_file"
rm "$local_file"

date +%s > /tmp/last_backup_success
echo "Backup complete."

if [ -n "$BACKUP_KEEP_DAYS" ]; then
  remove_old_backups
fi
