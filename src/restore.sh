#! /bin/sh

set -eu
set -o pipefail

source ./env.sh
source ./s3.sh

if [ -z "$PASSPHRASE" ]; then
  file_type=".dump"
else
  file_type=".dump.gpg"
fi

if [ $# -eq 1 ]; then
  s3_key="${S3_PREFIX}/${BACKUP_NAME_PREFIX}${POSTGRES_DATABASE}_$1${file_type}"
else
  echo "Finding latest backup..."
  s3_key=$(find_latest_backup_key)
fi

echo "Fetching backup from S3..."
aws_cmd s3 cp "s3://${S3_BUCKET}/${s3_key}" "db${file_type}"

if [ -n "$PASSPHRASE" ]; then
  echo "Decrypting backup..."
  gpg --decrypt --batch --passphrase "$PASSPHRASE" db.dump.gpg > db.dump
  rm db.dump.gpg
fi

echo "Restoring from backup..."
pg_restore -h "$POSTGRES_HOST" \
           -p "$POSTGRES_PORT" \
           -U "$POSTGRES_USER" \
           -d "$POSTGRES_DATABASE" \
           --clean --if-exists db.dump
rm db.dump

echo "Restore complete."
