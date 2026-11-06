#!/bin/sh
# Download Inter 4.1 and Literata 3.103 (both SIL OFL 1.1) into
# koreader/fonts/home/ and check them against fonts.sha256.
set -e
cd "$(dirname "$0")"
DEST=koreader/fonts/home
INTER=https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip
LITERATA=https://github.com/googlefonts/literata/releases/download/3.103/3.103.zip

if [ -d "$DEST" ] && (cd "$DEST" && sha256sum -c --quiet ../../../fonts.sha256) 2>/dev/null; then
    echo "fonts already present"; exit 0
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$DEST"
curl -fsSLo "$tmp/inter.zip" "$INTER"
curl -fsSLo "$tmp/literata.zip" "$LITERATA"
unzip -qjo "$tmp/inter.zip" 'extras/ttf/Inter-Regular.ttf' 'extras/ttf/Inter-Medium.ttf' \
    'extras/ttf/Inter-SemiBold.ttf' 'extras/ttf/Inter-Bold.ttf' -d "$DEST"
unzip -qjo "$tmp/literata.zip" 'fonts/ttf/Literata-*.ttf' -x 'fonts/ttf/Literata-Light*' \
    'fonts/ttf/Literata-ExtraLight*' 'fonts/ttf/Literata-SemiBold*' 'fonts/ttf/Literata-ExtraBold*' \
    'fonts/ttf/Literata-Black*' -d "$DEST"
unzip -p "$tmp/inter.zip" LICENSE.txt > "$DEST/Inter-LICENSE.txt"
unzip -p "$tmp/literata.zip" OFL.txt > "$DEST/Literata-OFL.txt"
(cd "$DEST" && sha256sum -c --quiet ../../../fonts.sha256)
echo "fonts ready in $DEST"
