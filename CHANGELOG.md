# Changelog

All notable changes to MeowWatch. Newest first. Each version header is
`## [<version>] - <date>`; the lines below it are that version's notes. The
release pipeline parses this file into `releases/changelog.json` on R2, which the
in-app updater reads to show what changed.

## [0.1.2-alpha] - 2026-05-30
- Resize the chat card from any of its four corners (the opposite corner stays pinned).
- Card now has a real height you can drag (fixes height resize doing nothing).
- Hover a corner to get a resize cursor; the chat-card buttons have hover tooltips.
- Card keeps its physical size when you maximize or resize the window (no longer scales with it).
- Updater shows a scrollable changelog covering every version between your build and the latest.

## [0.1.1-alpha] - 2026-05-30
- Resizable chat card: drag the corner grip to set its size, with a reset button.
- The chosen card size is saved locally and restored on the next launch.

## [0.1.0-alpha] - 2026-05-30
- First alpha. Load a local video and co-watch in sync with a friend over a public Syncplay room.
- Floating glass chat overlay: drag to any corner, collapse to a peek tab, send messages, reactions, typing indicator.
- Connect screen with saved room profiles and continue-watching history.
- Three themes (Cozy, Cinema Noir, Glass Aurora) with live switching.
- Auto-update: in-app version check, download, and one-click install from a Cloudflare R2 release bucket.
