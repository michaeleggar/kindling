# kindling

A Kindle is a stack of paper waiting for a match. These are the mods I used to burn the Amazon UI off my jailbroken Kindle Paperwhite (6th gen) and put a KOReader setup in its place: a real home screen, calmer menus, books delivered from Dropbox, and screensavers that aren't ads. The store and its "Customers also bought" rows went up with the rest of the kindling.

Built on KOReader v2026.07.1.

## What's here

| Path | What it does |
| --- | --- |
| `koreader/plugins/homescreen.koplugin` | Home screen for `/mnt/us/library`. Shows what you're reading first, then each section as covers or a title list, and marks new books. |
| `koreader/plugins/kindleui.koplugin` | Simpler settings, reading controls, and contents and text sheets, styled to match the home screen. |
| `koreader/plugins/dropboxsync.koplugin` | Runs `rclone/sync-books.sh` to pull new books from `Dropbox:/Library` and shows how the last sync went. |
| `koreader/patches/2-home-ui.lua` | User patch that restyles KOReader's menus and popups with Inter, thinner frames, rounder corners, and lighter dividers. |
| `koreader/styletweaks/` | Custom CSS style tweaks. `Calm_chapter_headings.css` tones down chapter headings. |
| `koreader/icons/kindleui.*.svg` | Icons for the Kindle UI plugin. |
| `koreader/settings/gestures.lua` | My gesture mappings. |
| `rclone/sync-books.sh` | One-way copy from Dropbox to the Kindle, with a lock file and a status file. |
| `screensavers/` | Generative screensavers: halftones, dithering, and patterns. |

## Install

The scripts expect `ssh kindle` to reach the device (KOReader's SSH plugin listens on port 2222).

```sh
./install.sh          # push everything to the Kindle
./pull.sh             # copy on-device edits back into the repo, then review with git diff
```

Restart KOReader after installing.

### What you need to add yourself

The patch and plugins expect these fonts in `/mnt/us/koreader/fonts/home/`:

- [Inter](https://rsms.me/inter/) in Regular, Medium, SemiBold, and Bold
- [Literata](https://fonts.google.com/specimen/Literata) in Regular, Italic, Medium, MediumItalic, Bold, and BoldItalic

For Dropbox sync, download the `linux-arm-v7` build of rclone from [rclone.org](https://rclone.org/downloads/) and put the binary at `/mnt/us/rclone/rclone`. Then run `rclone config` on a computer to authorize Dropbox, and copy the remote it creates (named `dropbox`) to `/mnt/us/rclone/rclone.conf`. `rclone/rclone.conf.example` shows the format. Don't commit the real file, because it holds your Dropbox token.

## Paths

The library location (`/mnt/us/library`) and the Dropbox folder (`Dropbox:/Library`) are hard-coded near the top of `homescreen.koplugin/main.lua`, `dropboxsync.koplugin/main.lua`, and `sync-books.sh`. Change them there if your setup differs.
