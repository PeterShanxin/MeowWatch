# Changelog

All notable changes to MeowWatch. Newest first. Each version header is
`## [<version>] - <date>`; the lines below it are that version's notes. The
release pipeline parses this file into `releases/changelog.json` on R2, which the
in-app updater reads to show what changed.

## [0.9.0-alpha] - 2026-06-01
- Unread chat messages no longer vanish when the screen goes idle: a collapsed chat keeps its unread badge fully visible, and a new "Fully wake chat on message" setting lets an open chat brighten back up (instead of staying dimmed) when a message arrives.

## [0.8.1-alpha] - 2026-05-31
- Fixed white screen bug when resizing chat card by hiding drop zones during resize.

## [0.8.0-alpha] - 2026-05-31
- You now see your own playback actions too: when you pause, resume, or skip, a little banner and a chat line confirm it ("⏸ you paused at 12:30", "⏩ you skipped to 45:00") — the same way you already see your friend's actions. No more wondering whether your click registered.
- Skipping around no longer floods the chat. Dragging the scrubber or holding the seek keys used to spit out a "skipped to…" line for every step; now it waits until you settle and posts a single line for where you landed.
- After you've been idle a little longer during playback, the dimmed chat card now fades away completely instead of lingering as a faint ghost — so the video is fully unobstructed. It snaps right back the moment you move the mouse or press a key.

## [0.7.0-alpha] - 2026-05-31
- MeowWatch now checks for updates on its own when you open it. If a newer version is out, the version chip in the bottom-right corner gets a little amber dot and a "New version available!" message pops up with an Update button — tap it to open the updater. No more remembering to check by hand. The check runs quietly once per launch and never gets in your way.

## [0.6.0-alpha] - 2026-05-31
- The player now gets out of your way while you watch. After a few seconds of no mouse or keyboard activity during playback, the controls, the top-left gear, and the emoji reaction bar fade away, and the chat card dims down — so nothing covers the video. Everything snaps back the instant you move the mouse, scroll, tap, or press a key (or whenever playback pauses).
- New "Dim chat when idle" toggle in the gear menu: leave it on to fade the open chat to a faint ghost while idle, or turn it off to keep chat fully visible. Your choice is remembered.

## [0.5.0-alpha] - 2026-05-31
- Chat now shows how many messages you haven't read: a red count rides the collapsed tab, and an "↓ N new messages" pill appears in the open chat when you've scrolled up. Tap the pill (or scroll to the bottom) to catch up and clear it.
- A soft notification chime plays when a friend messages you while the window isn't focused, so you don't miss it while doing something else.

## [0.4.1-alpha] - 2026-05-31
- Reopening the chat now reliably jumps straight to the newest message, even when a backlog piled up while it was hidden — it no longer occasionally stuck at the top.
- The "… is typing" line no longer nudges the chat list up and down as your friend starts and stops typing; its space is always reserved and the text just fades in and out.

## [0.4.0-alpha] - 2026-05-31
- When your friend pauses, resumes, or jumps to a different spot, a little note now pops up over the video and in chat (e.g. "lin skipped to 45:00") so you know why playback moved. Your own actions stay quiet.

## [0.3.1-alpha] - 2026-05-31
- Fixed auto-update silently doing nothing when you clicked Install: the updater is now launched so it keeps running after the app closes, instead of being killed the instant the app exited. Updating from this version onward applies the new version and restarts correctly.

## [0.3.0-alpha] - 2026-05-31
- The version button (bottom-right) now shows a "What's new" changelog even when you're already up to date — tap it any time to see what changed in recent versions.

## [0.2.0-alpha] - 2026-05-31
- Chat input keeps focus after you send a message, so you can keep typing without clicking back into the box.
- The chat list scrolls to the newest message automatically — when a message arrives, and when you reopen the chat after messages piled up while it was hidden.

## [0.1.3-alpha] - 2026-05-31
- Fixed auto-update never actually applying: it now replaces the app's files correctly and restarts, instead of leaving you on the old version.
- Auto-updates now verify the download's SHA-256 fingerprint before installing, so a corrupted or tampered download is rejected instead of applied.

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
