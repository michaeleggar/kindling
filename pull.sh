#!/bin/sh
# Copy the current mods from the Kindle back into this repo, so on-device
# edits can be reviewed with `git diff` and committed.
# Only tracked paths are pulled; secrets and personal data stay on the device.
set -e
HOST=${1:-kindle}
cd "$(dirname "$0")"

ssh "$HOST" 'cd /mnt/us && tar cf - \
    koreader/plugins/kindleui.koplugin koreader/plugins/homescreen.koplugin \
    koreader/plugins/dropboxsync.koplugin \
    koreader/patches koreader/styletweaks koreader/icons \
    koreader/settings/gestures.lua \
    rclone/sync-books.sh screensavers' | tar xf -
git status --short
