# Changelog

All notable changes to MeowWatch. Newest first. Each version header is
`## [<version>] - <date>`; the lines below it are that version's notes. The
release pipeline parses this file into `releases/changelog.json` on R2, which the
in-app updater reads to show what changed.

## [0.19.0-alpha] - 2026-06-07
- When you join a Syncplay room, chat now greets you with who is already there — "Alice, Bob are in the room — say hi ~" — or tells you the room is empty so you know you're waiting. (#90)
- Loading a video file no longer shows a misleading "jumped to 00:00" system message. Instead you see "Loaded matching file — you're in sync!" when your file matches your friend's, or simply "Loaded <filename>" otherwise. (#91)

## [0.18.0-alpha] - 2026-06-07
- The mouse cursor now hides automatically when you've been watching without touching the mouse for a few seconds, just like the playback bar and chat overlay. Move the mouse and everything — including the cursor — reappears instantly. (#78)
- The volume button in the playback bar is now a proper volume control: hover over it to reveal a vertical slider you can drag to any level, or click it to mute and unmute. The level you set is remembered, so unmuting restores it instead of jumping back to full. (#80)
- The play/pause and mute buttons now respond instantly to a click instead of feeling sluggish, and double-clicking either one no longer accidentally toggles fullscreen. (Previously the double-click-to-fullscreen detection on the video held every button click for a fraction of a second before it registered.)

## [0.17.0-alpha] - 2026-06-04
- MeowWatch now sets `video-sync=display-resample` so mpv locks each frame to your monitor's refresh cycle instead of the audio clock. In practice this means smoother motion and fewer dropped or stuttered frames, especially on high-refresh displays. The change comes with a tiny CPU cost from audio resampling to keep audio and video locked together. If you ever need to revert to the old behaviour (e.g. for a VRR display or sync debugging), set `MEOWWATCH_FORCE_AUDIO_SYNC=1` before launching. (#74)

## [0.16.1-alpha] - 2026-06-04
- Fixed two long-standing room glitches. First, your own chat messages could show up as if a friend sent them (and vice-versa) after a brief disconnect — the server sometimes hands you a slightly different name when you rejoin, and ownership was decided by comparing names. Each message now remembers whether *you* sent it the moment it arrives, so it stays correct no matter how your name shifts during the session. Second, "continue watching" a file from your history now rejoins the exact room you watched it in, instead of dropping you into whatever room you used most recently. (#40, #77)

## [0.16.0-alpha] - 2026-06-04
- On Windows, MeowWatch now asks the graphics chip for a "zero-copy" hardware decode path (`d3d11va`) instead of letting the player pick whatever it likes. The old default sometimes decoded a frame on the GPU, copied it down to ordinary memory, then pushed it back up to the GPU to draw — a wasteful round-trip. The new path keeps each frame on the GPU the whole time, which cuts memory traffic and power draw, most noticeably on Snapdragon X / ARM laptops. If your machine can't do this, the player quietly falls back to software decoding as before, so nothing breaks. Other platforms (macOS, Linux) are unchanged. (#72)

## [0.15.2-alpha] - 2026-06-04
- Maintenance only, nothing changes in the app: updated the behind-the-scenes build-and-release machinery to the latest tooling that GitHub now requires, and fixed how the release packages the download so updates keep building and shipping to you without interruption.

## [0.15.0-alpha] - 2026-06-03
- An under-the-hood design-system pass: every text size, spacing, corner radius, and animation timing across the app now comes from one small, consistent set of values instead of being hand-picked screen by screen. Most of this is invisible — the cozy look is unchanged — but a handful of spots tighten up by a pixel or two so the whole app feels more uniform. Also adds a hidden "design gallery" (long-press the version badge) that shows every style token and component live across all three themes, for tuning the look as the app grows.

## [0.14.0-alpha] - 2026-06-03
- The playback bar now has a volume button. Click it to mute, click again to restore the level you were at — and the icon shows at a glance whether sound is off, low, or up. (#45)
- Fixed the chat overlay's drag-to-move handle so it no longer sits underneath the corner resize grip. The move icon now sits clear of the corner, so grabbing it reliably moves the card instead of accidentally starting a resize. (#7)

## [0.13.0-alpha] - 2026-06-03
- MeowWatch now plays video using your computer's built-in graphics hardware decoder by default, instead of grinding through every frame on the CPU. On a Snapdragon X / ARM laptop (and any machine with a capable graphics chip) that means much lower CPU use, noticeably better battery, less heat and fan noise, and smoother playback — most of all on 4K or HEVC files. Machines without a usable hardware decoder fall back to the old software decoding automatically, so nothing breaks anywhere. (Software decoding can still be forced with the `MEOWWATCH_FORCE_SW_DECODE` environment variable, which is only needed when running two app instances on one PC for local sync testing.)

## [0.12.1-alpha] - 2026-06-02
- The quiet "felt" sound now also plays when a message arrives while the chat is dimmed or hidden by idle — not just when it's collapsed. So if the expanded chat has faded into the idle dim (or fully vanished in deep idle) while the video plays, you'll still get the soft nudge, since you can't read it then either. With chat open and fully visible, or paused, it stays silent as before (#58).

## [0.12.0-alpha] - 2026-06-02
- New notification sounds you can pick from. There are now two: a clearer "notification sound" that plays when MeowWatch is in the background, and a softer "quiet sound" that's just felt when a message arrives while the chat is hidden and the video is playing — so you're nudged without being yanked off the video. Choose either in the gear → Settings, each with a ▶ preview button (#58).
- System/sync lines (like a friend pausing or seeking) no longer make a notification sound — only real chat messages do (#57).

## [0.11.0-alpha] - 2026-06-02
- You can now select and copy chat messages — drag across a message to grab links, timestamps, or quotes (#54).
- When a friend is typing, the collapsed chat tab now lights up and shows a little animated "…" so you can tell someone's writing without opening the chat (#53).
- If a friend starts playback before you've loaded a video, the start screen now tells you ("lin started playback — load a video to join") instead of it happening silently. And if you've loaded a video but your friend hasn't yet, you now see a "⏳ lin hasn't loaded a video yet" heads-up — so neither side is left guessing (#60).
- The gear menu now hides the "Fully wake chat on message" switch unless "Dim chat when idle" is on — it did nothing in that state. It slides in and out smoothly instead of popping (#51).
- If you've downloaded an update but haven't installed it, closing the app now offers to install it on the way out, with an "installing…" notice so it doesn't look frozen, then starts you on the new version next time instead of nagging you to download it again. A normal close (no pending update) is untouched and instant (#62).
- The dimmed idle chat is more readable now, and you can tune exactly how faint it gets with a new "Dimmed chat readability" slider (with a reset) under the gear's Settings. A new message still brightens it and it settles back to hidden if you don't touch it.
- The gear menu's chat settings now live under a collapsible "Settings" section so the menu stays short, with the wake toggle and dim slider sliding in only when "Dim chat when idle" is on.
- Fixed playback jumping to 00:00 after a reconnect: when both sides briefly drop together, the app no longer yanks a mid-film session back to the start.

## [0.10.6-alpha] - 2026-06-02
- Long chat messages are no longer silently cut off. The message box now caps at 150 characters (the server's limit) and shows a counter as you near it, so nothing gets eaten mid-word on send (#55).
- Shift+Enter now starts a new line in chat instead of sending. Plain Enter still sends, and the box grows to fit a multi-line message (#56).
- Your typed-but-unsent chat draft no longer vanishes when you click away from the window and back, minimize and restore, or collapse the chat — it's kept until you send or clear it (#59).
- The "update available" pop-up now has a close (✕) button so you can dismiss it on the spot instead of waiting for it to fade (#61).
- The update download bar no longer looks frozen at 0%. When the server doesn't report a file size, it now shows a moving "downloading…" bar with the amount downloaded so far, instead of a stuck empty bar (#63).

## [0.10.5-alpha] - 2026-06-02
- Fixed your name getting swapped when you used "Continue watching". Resuming a file now rejoins under the name you watched it as (instead of silently falling back to the default "meow"), and if the server has to rename you to avoid a clash, the app now follows that rename — so chat bubbles, the typing indicator and the member list all show the right person instead of flipping you and your friend around (#40).

## [0.10.4-alpha] - 2026-06-02
- Fixed a bug where incoming messages while you were idle would not wake the dimmed chat card (it would stay dimmed as a ghost).
- System messages (like "friend joined") no longer incorrectly trigger the unread badge or the "New Messages" divider in the chat.

## [0.10.3-alpha] - 2026-06-01
- Resizing the chat card no longer washes the whole screen pale-white. Dragging a corner grip used to flash the player (or, in a room, the waiting screen) white for the whole drag; it's now gone and the resize is smooth (#50).

## [0.10.2-alpha] - 2026-06-01
- Fixed a silent disconnect where the app could look "connected" while the link was actually dead. If the connection drops in a way that doesn't cleanly close (server hiccup, Wi-Fi blip, router idle-timeout), MeowWatch now notices the missing heartbeat within ~12 seconds, shows "reconnecting", and automatically dials back into the room — no more typing messages into the void or having to kill and relaunch.
- "Leave room" no longer hangs on a half-dead connection — leaving is now immediate.

## [0.10.1-alpha] - 2026-06-01
- Leaving the player no longer leaves the app stuck fullscreen — the window goes back to normal when you exit the video (#23).
- Auto-pause messages now tell the truth about why. When a friend leaves, you'll see "[Friend] left, auto-paused"; when you simply lose connection, it stays the generic "lost sync with your friend" instead of wrongly blaming someone for leaving. The "you paused" line also no longer pops up when you're alone in the room (#41).

## [0.10.0-alpha] - 2026-06-01
- Update downloads no longer get thrown away when you close the updater. If you start a download and dismiss the dialog, it keeps going in the background — reopen the updater later and it's still downloading (or ready to install) right where it left off.
- The open chat now marks where you left off: when new messages arrive while you've scrolled up, a "New Messages" divider drops in above the first unread one. It clears itself once you scroll to the bottom (after a short moment) or start typing a reply.

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
