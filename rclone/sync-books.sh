#!/bin/sh
# Copy new and changed files from Dropbox:/Library into /mnt/us/library.
# Writes "running", then "ok <new file count>" or "error" to $DIR/status.
DIR=/mnt/us/rclone
DEST=/mnt/us/library
LOCK=$DIR/lock

if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

echo running > "$DIR/status"
mkdir -p "$DEST"
count() { find "$DEST" -type f ! -path "*.sdr/*" | wc -l; }
before=$(count)

SSL_CERT_FILE=/mnt/us/koreader/data/ca-bundle.crt "$DIR/rclone" \
    --config "$DIR/rclone.conf" \
    copy dropbox:/Library "$DEST" \
    --exclude ".*" --exclude "/*.md" \
    --log-file "$DIR/sync.log" --log-level INFO

if [ $? -eq 0 ]; then
    after=$(count)
    echo "ok $((after - before))" > "$DIR/status"
    date +%s > "$DIR/last_sync"
else
    echo error > "$DIR/status"
fi
