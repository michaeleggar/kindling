#!/bin/sh
# Push the mods in this repo to the Kindle over SSH.
# Usage: ./install.sh [ssh-host]   (default host: kindle)
# Restart KOReader afterwards to load plugin and patch changes.
set -e
HOST=${1:-kindle}
cd "$(dirname "$0")"

tar cf - \
    koreader/plugins koreader/patches koreader/styletweaks koreader/icons \
    koreader/settings/gestures.lua \
    rclone/sync-books.sh \
    screensavers \
  | ssh "$HOST" 'cd /mnt/us && tar xf - && chmod +x rclone/sync-books.sh'

ssh "$HOST" 'test -f /mnt/us/rclone/rclone.conf' \
    || echo "note: /mnt/us/rclone/rclone.conf is missing; see rclone/rclone.conf.example"
ssh "$HOST" 'test -x /mnt/us/rclone/rclone' \
    || echo "note: /mnt/us/rclone/rclone binary is missing; see README"
ssh "$HOST" 'ls /mnt/us/koreader/fonts/home/Inter-Regular.ttf >/dev/null 2>&1' \
    || echo "note: fonts missing from /mnt/us/koreader/fonts/home; see README"
echo "installed to $HOST"
