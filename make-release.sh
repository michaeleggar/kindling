#!/bin/sh
# Build per-component zips in dist/ for a GitHub release.
# Each zip unpacks onto the Kindle's root storage (/mnt/us, the USB drive),
# with fonts and their licenses bundled where needed.
set -e
cd "$(dirname "$0")"
./fetch-fonts.sh >/dev/null
rm -rf dist && mkdir dist
python3 -I - "$@" <<'PY'
import os, zipfile
F = ["koreader/fonts/home"]
comps = {
    "homescreen":   ["koreader/plugins/homescreen.koplugin"] + F,
    "kindleui":     ["koreader/plugins/kindleui.koplugin", "koreader/icons"] + F,
    "menus":        ["koreader/patches/2-home-ui.lua"] + F,
    "dropboxsync":  ["koreader/plugins/dropboxsync.koplugin", "rclone/sync-books.sh", "rclone/rclone.conf.example"],
    "styletweaks":  ["koreader/styletweaks"],
    "screensavers": ["screensavers"],
}
comps["kindling-all"] = sorted({p for v in comps.values() for p in v})
def walk(p):
    if os.path.isfile(p): yield p; return
    for root, _, files in os.walk(p):
        for f in sorted(files): yield os.path.join(root, f)
for name, paths in comps.items():
    out = f"dist/{name}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in paths:
            for f in walk(p):
                z.write(f, f)
        z.write("LICENSE", "kindling-LICENSE")
    print(out, os.path.getsize(out) // 1024, "KB")
PY
