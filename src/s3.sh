# S3 helper functions. Requires env.sh to be sourced first.

aws_cmd() {
  if [ -n "$S3_ENDPOINT" ]; then
    aws --endpoint-url "$S3_ENDPOINT" "$@"
  else
    aws "$@"
  fi
}

format_date_from_epoch() {
  epoch="$1"
  date -u -d "@${epoch}" +%Y-%m-%d
}

key_matches_file_type() {
  key="$1"
  suffix="$2"
  rest="${key%$suffix}"
  [ "$rest" != "$key" ]
}

s3_key_from_uri() {
  uri="$1"
  without_scheme="${uri#s3://}"
  echo "${without_scheme#*/}"
}

verify_s3_upload() {
  s3_uri="$1"
  local_file="$2"
  local_size=$(wc -c < "$local_file" | tr -d ' ')
  key=$(s3_key_from_uri "$s3_uri")
  remote_size=$(aws_cmd s3api head-object \
    --bucket "$S3_BUCKET" \
    --key "$key" \
    --query 'ContentLength' \
    --output text)
  if [ "$local_size" != "$remote_size" ]; then
    echo "Upload verification failed: local size=$local_size, remote size=$remote_size" >&2
    return 1
  fi
  echo "Upload verified ($remote_size bytes)."
}

find_latest_backup_key() {
  search_prefix="${S3_PREFIX}/${BACKUP_NAME_PREFIX}${POSTGRES_DATABASE}"
  latest_key=""
  latest_modified=""
  token=""

  while :; do
    if [ -n "$token" ]; then
      page=$(aws_cmd s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$search_prefix" \
        --continuation-token "$token" \
        --query 'Contents[*].[Key,LastModified]' \
        --output text)
      token=$(aws_cmd s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$search_prefix" \
        --continuation-token "$token" \
        --query 'NextContinuationToken' \
        --output text)
    else
      page=$(aws_cmd s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$search_prefix" \
        --query 'Contents[*].[Key,LastModified]' \
        --output text)
      token=$(aws_cmd s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$search_prefix" \
        --query 'NextContinuationToken' \
        --output text)
    fi

    if [ -n "$page" ] && [ "$page" != "None" ]; then
      while IFS='	' read -r key modified; do
        [ -z "$key" ] && continue
        if ! key_matches_file_type "$key" "$file_type"; then
          continue
        fi
        if [ -z "$latest_modified" ] || [ "$modified" \> "$latest_modified" ]; then
          latest_modified="$modified"
          latest_key="$key"
        fi
      done <<EOF
$page
EOF
    fi

    case "$token" in
      None|'') break ;;
    esac
  done

  if [ -z "$latest_key" ]; then
    echo "No backups found with prefix ${search_prefix}" >&2
    return 1
  fi

  echo "$latest_key"
}

remove_old_backups() {
  sec=$((86400 * BACKUP_KEEP_DAYS))
  cutoff_epoch=$(($(date +%s) - sec))
  date_from_remove=$(format_date_from_epoch "$cutoff_epoch")
  token=""

  echo "Removing backups older than $BACKUP_KEEP_DAYS days from $S3_BUCKET..."

  while :; do
    if [ -n "$token" ]; then
      page=$(aws_cmd s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$S3_PREFIX" \
        --continuation-token "$token" \
        --query 'Contents[*].[Key,LastModified]' \
        --output text)
      token=$(aws_cmd s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$S3_PREFIX" \
        --continuation-token "$token" \
        --query 'NextContinuationToken' \
        --output text)
    else
      page=$(aws_cmd s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$S3_PREFIX" \
        --query 'Contents[*].[Key,LastModified]' \
        --output text)
      token=$(aws_cmd s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$S3_PREFIX" \
        --query 'NextContinuationToken' \
        --output text)
    fi

    if [ -n "$page" ] && [ "$page" != "None" ]; then
      while IFS='	' read -r key modified; do
        [ -z "$key" ] && continue
        modified_date=${modified%%T*}
        if [ "$modified_date" != "$date_from_remove" ] && [ "$modified_date" \< "$date_from_remove" ]; then
          echo "Removing s3://${S3_BUCKET}/${key} (modified ${modified})"
          aws_cmd s3 rm "s3://${S3_BUCKET}/${key}"
        fi
      done <<EOF
$page
EOF
    fi

    case "$token" in
      None|'') break ;;
    esac
  done

  echo "Removal complete."
}
