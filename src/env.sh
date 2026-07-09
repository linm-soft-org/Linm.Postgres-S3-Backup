if [ -z "$S3_BUCKET" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ -z "$POSTGRES_DATABASE" ]; then
  echo "You need to set the POSTGRES_DATABASE environment variable."
  exit 1
fi

if [ -z "$POSTGRES_HOST" ]; then
  # https://docs.docker.com/network/links/#environment-variables
  if [ -n "$POSTGRES_PORT_5432_TCP_ADDR" ]; then
    POSTGRES_HOST=$POSTGRES_PORT_5432_TCP_ADDR
    POSTGRES_PORT=$POSTGRES_PORT_5432_TCP_PORT
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

if [ -z "$POSTGRES_USER" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable."
  exit 1
fi

if [ -z "$POSTGRES_PORT" ]; then
  POSTGRES_PORT=5432
fi

if [ -z "$S3_PREFIX" ]; then
  if [ -n "${S3_PATH:-}" ]; then
    S3_PREFIX="$S3_PATH"
  else
    S3_PREFIX="backup"
  fi
fi
# Normalize folder prefix (no leading/trailing slash)
S3_PREFIX="${S3_PREFIX#/}"
S3_PREFIX="${S3_PREFIX%/}"

# Optional filename prefix before POSTGRES_DATABASE (e.g. reva-prod → reva-prod_railway_2026-01-01T....dump)
if [ -n "${BACKUP_FILE_PREFIX:-}" ]; then
  BACKUP_FILE_PREFIX="${BACKUP_FILE_PREFIX#/}"
  BACKUP_FILE_PREFIX="${BACKUP_FILE_PREFIX%/}"
  BACKUP_NAME_PREFIX="${BACKUP_FILE_PREFIX}_"
else
  BACKUP_NAME_PREFIX=""
fi

if [ -n "$BACKUP_KEEP_DAYS" ]; then
  case "$BACKUP_KEEP_DAYS" in
    *[!0-9]*)
      echo "BACKUP_KEEP_DAYS must be a positive integer." >&2
      exit 1
      ;;
  esac
fi

if [ -n "$S3_ACCESS_KEY_ID" ]; then
  export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
fi
if [ -n "$S3_SECRET_ACCESS_KEY" ]; then
  export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
fi
export AWS_DEFAULT_REGION=$S3_REGION
export PGPASSWORD=$POSTGRES_PASSWORD
