# Changelog

All notable changes to MeowWatch. Newest first. Each version header is
`## [<version>] - <date>`; the lines below it are that version's notes. The
release pipeline parses this file into `releases/changelog.json` on R2, which the
in-app updater reads to show what changed.

## [0.30.1-alpha] - 2026-06-20
- Fixed a sync hiccup where pausing and then resuming too quickly could leave your friend's side stuck: their video froze on a single frame while the app reported it as playing, and your side kept rewinding over and over trying to catch up to the frozen spot. MeowWatch now watches whether a resume actually starts moving — if it stalls for a couple of seconds it quietly nudges the player (re-seek and play) to get it going again. It's the automatic version of the pause-wait-a-moment-then-resume trick that used to fix it by hand.

## [0.30.0-alpha] - 2026-06-19
- Connect screen polish: Advanced server, port, and server-password fields now show a small reset icon only after you change them, with a hover tooltip and a quick "Advanced setting updated." confirmation when you leave an edited field. Continue Watching and Saved Rooms now keep their saved identity when you click the main card, and when your typed name differs they offer a clear "Join as <name> this time" action instead of silently overwriting the saved name. (#138)
- Tightened the new resume-name flow after manual testing: the "Join as <name> this time" row now grows and un-grows more gently instead of snapping the card shape, the name field stays visually stable while entering or leaving a saved room, keeps your typed name when you return, and now has an in-field clear button. Rooms can also be left immediately from the no-video screen without first loading a video.

## [0.29.4-alpha] - 2026-06-19
- Made the "I left the room" goodbye more reliable when you close the app with the X button. The previous fix sent that goodbye and gave it a brief moment to go out, but on a normal close the app didn't actually wait for that moment to finish before quitting — so it could quit mid-send and your friend would briefly see "lost connection" instead of "left the room". The window still hides instantly (so closing still feels instant), but the app now waits the short, capped moment for the goodbye to finish leaving before it shuts down. The wait is bounded with a hard-timeout backstop, so a dead network still can't make closing hang. (#148)

## [0.29.3-alpha] - 2026-06-19
- Fixed a Windows close bug where clicking X while in a room could make the window disappear but leave MeowWatch secretly running in the background, still saving playback position and sometimes keeping audio/player resources alive. Closing now gives the room-leave message a short best-effort chance, flushes the log, tears down the window, and then exits the process explicitly so there is no hidden headless instance left behind. (#148)

## [0.29.2-alpha] - 2026-06-19
- Fixed the 0.29.1 co-watch regression where your friend could resume and your app would show the sync notification, but the video stayed paused. The follower was seeking to the right timestamp first, but on some paused media_kit/mpv paths that seek command reported its new position while its Future stayed unfinished, so MeowWatch never sent the follow-up Play command. Remote resume now treats player command Futures as best-effort, wakes playback after the seek visibly lands (or after a short wait), and re-seeks after Play if needed so later pause/seek commands cannot get stuck behind one slow backend Future.

## [0.29.1-alpha] - 2026-06-17
- Fixed a bug where **switching to a different video — like loading the next episode — could get stuck on the "Couldn't play that video / Timed out" error screen**, even though the file was perfectly fine; you'd have to reload and press Play to get past it. MeowWatch opens a video paused on purpose (so you and your friend don't both jump to the start), and a recent change started waiting for the player to *prove* the file opened before continuing. The proof only appears once the video actually decodes a frame — and after the first video, the shared player decodes nothing while paused, so the second file you loaded would sit there with no proof and time out. (The very first video after launching opened fine; it was switching files afterwards that hung.) On load, MeowWatch now nudges the player to decode the opening frame (muted, then straight back to paused at the start) so every file proves it opened right away — no reload, no Play needed. This also clears the related "keeps rewinding to sync" loop that kicked in when one of you was stuck on that error screen while the other kept playing. (#147)
- Fixed **co-watching constantly falling out of sync — the "keeps rewinding to catch up" loop** that made watching together unusable (0.28.0 was the last version that synced cleanly). When your friend pauses, plays, or jumps, your player takes a moment to follow along — and during that moment it could briefly report an old, not-yet-updated position to the room. Your friend would then "correct" to that stale spot, you'd correct back, and you'd yank each other around endlessly. MeowWatch now ignores those in-between position reports while it's busy following your friend, so it only ever shares your real position. (The shared-player change in 0.28.1 made those stale reports far more frequent, which is when this started.) (#147)
- Fixed a co-watch sync bug where a follower could show the "friend played / paused / jumped" notification while its video stayed still. Peer play/pause/seek events now reach the local player immediately instead of only updating the sync heartbeat cache, and local seek jumps are sent as real seeks even when the video backend reports a pause/play blip at the landing point. (#147)

## [0.29.0-alpha] - 2026-06-16
- The built-in diagnostic log now records **everything the app does**, not just the chat/sync traffic it used to. It captures loading a video, errors from the player, leaving a room, saving your spot, settings changes, and update downloads — across the whole time the app is open (the lobby and every room), all in one file. So if something freezes or misbehaves, a single exported log is enough to pinpoint where it got stuck — the kind of trouble the old log couldn't see at all. The detailed firehose (every play/pause/seek tick) is still kept only on the "verbose" setting; "neat" keeps just the meaningful events, and "off" still writes nothing. Links are always stored with any private access token stripped out. (#140)

## [0.28.3-alpha] - 2026-06-16
- Pausing now lines your friend up on the exact same timestamp, even for tiny differences under a quarter-second. That means frame-hunting moments - like pausing on a single surprising frame in a video - land on the same picture for both of you, while normal resume/play still avoids tiny jitter jumps.

## [0.28.2-alpha] - 2026-06-16
- Fixed a freeze where clicking **Load Video** could make the whole app go "Not Responding". The Windows "choose a file" box opens on the UI thread, and by default it lands on the *Quick access / Recent* view, which scans every recent, pinned, and cloud (OneDrive / network-drive) folder. On some machines one of those is slow or stuck, so the box never finished opening and the app waited forever. MeowWatch now opens the picker straight in a known-good local folder — your last-watched video's folder, falling back to your Videos folder — so it skips that flaky scan. (Like the leave-room freeze, whether it hit you depended on your PC's folders, so it affected some people and not others.) (#139)

## [0.28.1-alpha] - 2026-06-16
- Fixed a freeze where **leaving a room could lock up the Connect screen** — you'd land back on the start screen but nothing was clickable, and the app had to be force-closed. The cause was the video player shutting itself down at the moment you left; on some PCs that shutdown gets stuck and freezes the whole window. MeowWatch now keeps one video player running for the life of the app and simply empties it between rooms instead of tearing it down each time, so leaving a room is instant and the start screen stays responsive. (Whether this happened depended on your graphics card, which is why it hit some people and not others.) (#137)

## [0.28.0-alpha] - 2026-06-15
- Shared room codes are now **self-contained when you're on a non-default server**. If a host changes the server or port in Advanced settings, the code they copy now carries that address (e.g. `sleepy-otter-counts-cozy-stars@cozy.example.net:9000`), so a friend joins from a single paste instead of being told the server separately. Codes on the regular public server stay the exact same short magic sentence as before, and old codes like `happy-cat-11` still join unchanged. A self-hosted server *password* is deliberately never put in the code (it can't be truly hidden in a copy-pasteable code), so the joiner enters that once in Advanced — and a garbled code now shows a clear "copy it again" message instead of dropping you into the wrong room. (#110)

## [0.27.1-alpha] - 2026-06-15
- Tightened up video loading so quickly switching between videos can't briefly tug your friend's playback to the one you just left, and a hung or broken link can no longer be mistaken for a video that actually opened (which previously could happen if the previous video's data arrived a moment late). Both were narrow timing glitches around starting one video right as another finishes loading; everyday "load a video and watch together" is unchanged. (follow-up to #120)

## [0.27.0-alpha] - 2026-06-13
- You can now paste a direct video link and watch it together, instead of only loading a local file. The load screen has a new "or paste a direct video link" box (and there's a "Paste link…" item in the in-player gear menu), so you and a friend can both drop in the same `https://…/video.mp4` or `.m3u8` stream URL and stay in sync exactly like a shared file. If a link is unreachable, isn't actually a video, or has expired, you now get a clear "couldn't play that link" screen with Browse / Paste link / Try again buttons to recover — no more silent black screen. For room sync, a stream is shared by its URL (streams have no file size), following standard Syncplay behaviour. (#120)

## [0.26.0-alpha] - 2026-06-13
- The gear menu now shows a **"Now playing"** line with the name of the video you've got loaded, so anyone in the room can glance at the menu and confirm you're both on the same episode — no more guessing from the seek bar. Long filenames stay tidy (they wrap to two lines and trim with "…" rather than stretching the menu), and when nothing is loaded it simply says "Nothing loaded yet". (#133)
- Fixed a glitch where loading a **new episode right after the last one finished** could leave the player parked at the previous episode's end instead of jumping back to `0:00`. The old ending position could linger for a moment during the switch — and in a room that risked nudging your friend to the wrong spot — so the app now ignores any stale end-of-video position while the next file loads. (#132)

## [0.25.0-alpha] - 2026-06-13
- "Start new room" now copies a cute **magic sentence** instead of a code with a random tail — something like `sleepy-otter-counts-cozy-stars`. It's pleasant to read and say aloud, and its privacy now comes entirely from friendly words rather than a gibberish suffix like `…-k3pn`. There are ~700 million possible sentences (kept short so the room name fits the Syncplay server's length limit), so a friend can't stumble into your room by guessing. Paste the whole sentence into "Enter code from friend" to join. Your old room codes — bare `happy-cat-11` names and earlier `happy-cat-11-k3pn` private codes alike — keep working exactly as before, so saved rooms and any codes you've already shared still meet up. (#109)

## [0.24.0-alpha] - 2026-06-12
- The gear/settings menu is now reachable from the start screen, before you join a room — not just while watching. A new gear in the top-right of the connect screen opens the same settings you already know: theme, notification sounds, and diagnostic logging with its "Export logs…" button. So you can switch theme, pick your sounds, or grab the diagnostic logs without having to join a room first. (The in-room chat-dimming controls stay in the in-room gear, since there's no chat on the start screen.)

## [0.23.0-alpha] - 2026-06-11
- MeowWatch now keeps a rolling diagnostic log of each co-watch session on your PC, so when the occasional video-lag or broken-sound hiccup happens, the details are already saved instead of lost. It keeps the last 10 sessions and tidies up older ones automatically. A new "Diagnostic logging" control in the gear menu's Settings lets you pick how much detail to keep — Off, Neat, or Verbose (the default) — and an "Export logs…" button bundles them into a single file you can send over for a closer look.

## [0.22.2-alpha] - 2026-06-10
- Fixed a glitch where briefly reconnecting to your room could snap your video back to the very start and pause it. When the room momentarily empties during a reconnect, the server reports a blank "position 0, paused" state that belongs to nobody; the app used to follow it as if a friend had paused at the beginning. It now ignores any room state that isn't attributed to a real person, so a reconnect blip can no longer drag a mid-film session back to 00:00.

## [0.22.1-alpha] - 2026-06-10
- When your friend loads a video but hasn't pressed play yet, you now see a heads-up on your own load screen — `<friend> loaded "<file>" — load the same video to join` — so you know they're ready and waiting and which file to pick. Before, only the friend who loaded saw anything; the side still choosing a file got nothing unless the other person actually pressed play. (#116)
- Renamed the Advanced "Room password" field to "Server password — advanced / self-hosted only", with a note that it has no effect on the public server and that private rooms come from the code you share. The old label wrongly implied it could lock a public room; it only ever set a password for a self-hosted Syncplay server. (#117)

## [0.22.0-alpha] - 2026-06-10
- "Start new room" now makes your room private. The code it copies has a small secret word built onto the end (like `happy-cat-11-k3pn`), so only a friend you give the full code to can land in your room — someone who merely guesses the cute part ends up somewhere else. Paste the whole code into "Enter code from friend" and it joins automatically. Your old room-only codes still work exactly as before: share `happy-cat-11` on its own and you'll meet anyone using that same name, so existing saved rooms and codes you've shared keep working. The in-player gear menu now copies the full private code too, not just the room name. (#108)

## [0.21.2-alpha] - 2026-06-09
- After a quick reconnect to your room, the people list in the gear menu now always shows your own name the way you chose it — even when the server briefly adds a trailing underscore (like `meowPEOW_`) to avoid clashing with the ghost of your dropped session. Friends and chat still use the behind-the-scenes name so message ownership stays correct; only your own visible label is cleaned up. (#107)

## [0.21.1-alpha] - 2026-06-09
- Closing the app with the Windows X button while connected to a room now feels instant: the window disappears before the best-effort "left the room" signal runs, so a slow or wedged close hook cannot make the app look stuck. (#106)

## [0.21.0-alpha] - 2026-06-08
- When the app automatically rewinds your video to stay in sync with your friend (because your side had run ahead), you now see a gentle notice — a "🔄 Sync correction — rewound to 12:34" banner and a matching chat line — instead of playback silently jumping. It's worded as the app keeping you together, never as if someone deliberately skipped back, and repeated corrections are rate-limited so they can't spam the chat. (#98)

## [0.20.3-alpha] - 2026-06-08
- Fixed your name growing an extra "_" each time you reconnected (e.g. "meowPEOW" turning into "meowPEOW_", then "meowPEOW__"). The app now always asks the server for your original name on every reconnect, so the dedupe suffix can't pile up. (#93)
- Fixed a friend who already loaded a video showing as "hasn't loaded a video yet" after you reconnected. A leftover "ghost" of your own dropped session was being mistaken for your friend; the app now ignores that ghost and rebuilds who's really in the room — with their loaded files — fresh after each reconnect. (#93)

## [0.20.2-alpha] - 2026-06-08
- After installing an update, the app now comes back to the front instead of hiding behind your other windows.
- Fixed the empty PowerShell window that used to linger after an update restart — and closing it no longer closes the app along with it.

## [0.20.1-alpha] - 2026-06-07
- Closing the app with the window's X button now tells your friend you left the room, instead of showing them "lost connection" as if your network dropped. (#92)
- A friend who deliberately left and then comes back within a minute now shows as "joined the room" again, rather than "reconnected" — "reconnected" is now reserved for recovering from an actual connection drop. (#92)

## [0.20.0-alpha] - 2026-06-07
- The chat overlay now shows system messages when room members connect or disconnect. When a friend leaves deliberately you see "Alice left the room."; if they lose connection without warning you see "Alice lost connection." and then "Alice reconnected." if they come back within a minute. Your own reconnect after a blip shows "Connection lost — reconnecting…" and "Reconnected to room." so you know when you're back without messaging out-of-band. (#92)

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
