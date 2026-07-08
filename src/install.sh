#! /bin/sh

set -eux
set -o pipefail

GO_CRON_VERSION=0.0.5

apk update

apk add gnupg aws-cli

case "$TARGETARCH" in
  amd64)
    GO_CRON_SHA256=564c8291ef18879b300614e179cca3116506191cbc6b8e50448d274b256f2e67
    ;;
  arm64)
    GO_CRON_SHA256=adc760e969584a391e3d3d93facbc5a198d76981226f2d8c3b3b0217ac9c57d7
    ;;
  *)
    echo "Unsupported architecture: $TARGETARCH" >&2
    exit 1
    ;;
esac

apk add curl
GO_CRON_ARCHIVE="go-cron_${GO_CRON_VERSION}_linux_${TARGETARCH}.tar.gz"
curl -fsSL "https://github.com/ivoronin/go-cron/releases/download/v${GO_CRON_VERSION}/${GO_CRON_ARCHIVE}" -o "$GO_CRON_ARCHIVE"
echo "$GO_CRON_SHA256  $GO_CRON_ARCHIVE" | sha256sum -c -
tar xvf "$GO_CRON_ARCHIVE"
rm "$GO_CRON_ARCHIVE"
mv go-cron /usr/local/bin/go-cron
chmod u+x /usr/local/bin/go-cron
apk del curl

rm -rf /var/cache/apk/*
