# kindle-mods

My KOReader customizations for a jailbroken Kindle Paperwhite (6th gen), running KOReader v2026.07.1.

## What's here

| Path | What it does |
| --- | --- |
| `koreader/plugins/homescreen.koplugin` | A home screen for `/mnt/us/library`: a "continue reading" row, then each section shown as covers or as a title list. New books get a marker. |
| `koreader/plugins/kindleui.koplugin` | Simpler settings, reading controls, and sheets for contents and text options, styled to match the home screen. |
| `koreader/plugins/dropboxsync.koplugin` | Runs `rclone/sync-books.sh` to pull new books from `Dropbox:/Library` and shows the sync status. |
| `koreader/patches/2-home-ui.lua` | A user patch that restyles KOReader's menus and popups: Inter font, thinner frames, rounder corners, lighter dividers. |
| `koreader/styletweaks/` | Custom CSS style tweaks. `Calm_chapter_headings.css` tones down chapter headings. |
| `koreader/icons/kindleui.*.svg` | Icons used by the Kindle UI plugin. |
| `koreader/settings/gestures.lua` | My gesture mappings. |
| `rclone/sync-books.sh` | One-way Dropbox to Kindle copy, with a lock file and a status file. |
| `screensavers/` | Generative halftone, dither, and pattern screensavers. |

## Install

The scripts assume `ssh kindle` reaches the device (KOReader's SSH plugin listens on port 2222).

```sh
./install.sh          # push everything to the Kindle
./pull.sh             # copy on-device edits back into the repo, then review with git diff
```

Restart KOReader after installing.

### Not included, set these up yourself

- **Fonts.** The patch and plugins expect these files in `/mnt/us/koreader/fonts/home/`:
  - [Inter](https://rsms.me/inter/): Regular, Medium, SemiBold, Bold
  - [Literata](https://fonts.google.com/specimen/Literata): Regular, Italic, Medium, MediumItalic, Bold, BoldItalic
- **rclone.** Download the `linux-arm-v7` build from [rclone.org](https://rclone.org/downloads/) and put the binary at `/mnt/us/rclone/rclone`.
- **rclone config.** Run `rclone config` on a computer to authorize Dropbox. Then copy the resulting remote, named `dropbox`, to `/mnt/us/rclone/rclone.conf`. `rclone/rclone.conf.example` shows the format. **Never commit the real file**, because it holds your Dropbox token.

## Paths

The library location (`/mnt/us/library`) and the Dropbox folder (`Dropbox:/Library`) are hard-coded near the top of `homescreen.koplugin/main.lua`, `dropboxsync.koplugin/main.lua`, and `sync-books.sh`. Change them there if your setup is different.
