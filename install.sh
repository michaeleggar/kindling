#!/bin/sh
# Push mods from this repo to the Kindle over SSH.
#
# Usage: ./install.sh [-H host] [component ...]
#   default host is "kindle", default is every component.
#
# Components:
#   homescreen   home screen plugin (+ fonts)
#   kindleui     reading chrome, sheets and settings plugin (+ icons, fonts)
#   menus        2-home-ui patch restyling KOReader menus (+ fonts)
#   dropboxsync  Dropbox sync plugin and rclone/sync-books.sh
#   styletweaks  custom CSS style tweaks
#   gestures     my gesture mappings (replaces yours!)
#   screensavers generative screensavers in /mnt/us/screensavers
#
# Restart KOReader afterwards to load plugin and patch changes.
set -e
cd "$(dirname "$0")"

HOST=kindle
if [ "$1" = "-H" ]; then HOST=$2; shift 2; fi
[ $# -eq 0 ] && set -- homescreen kindleui menus dropboxsync styletweaks gestures screensavers

FONTS=
paths=
for c in "$@"; do
    case $c in
        homescreen)   paths="$paths koreader/plugins/homescreen.koplugin"; FONTS=1 ;;
        kindleui)     paths="$paths koreader/plugins/kindleui.koplugin koreader/icons"; FONTS=1 ;;
        menus)        paths="$paths koreader/patches/2-home-ui.lua"; FONTS=1 ;;
        dropboxsync)  paths="$paths koreader/plugins/dropboxsync.koplugin rclone/sync-books.sh" ;;
        styletweaks)  paths="$paths koreader/styletweaks" ;;
        gestures)     paths="$paths koreader/settings/gestures.lua" ;;
        screensavers) paths="$paths screensavers" ;;
        *) echo "unknown component: $c" >&2; exit 1 ;;
    esac
done
if [ -n "$FONTS" ]; then
    ./fetch-fonts.sh
    paths="$paths koreader/fonts/home"
fi

# shellcheck disable=SC2086
tar cf - $paths | ssh "$HOST" 'cd /mnt/us && tar xf - && { [ ! -f rclone/sync-books.sh ] || chmod +x rclone/sync-books.sh; }'

case " $* " in *" dropboxsync "*)
    ssh "$HOST" 'test -x /mnt/us/rclone/rclone' \
        || echo "note: /mnt/us/rclone/rclone is missing; see README"
    ssh "$HOST" 'test -f /mnt/us/rclone/rclone.conf' \
        || echo "note: /mnt/us/rclone/rclone.conf is missing; see rclone/rclone.conf.example"
esac
echo "installed to $HOST:$paths"
