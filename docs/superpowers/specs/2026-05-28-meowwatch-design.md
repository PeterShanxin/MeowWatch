# MeowWatch — Design Spec

**Date:** 2026-05-28
**Author:** shanxin (with Claude)
**Status:** Approved for planning

---

## 1. Purpose

A single-window desktop app that combines synchronized video playback with chat for co-watching with a friend. Replaces the current two-window setup (Syncplay + mpv.net) with one cohesive, polished application.

Audience: shanxin + one friend. Personal-toy scope. Polish prioritized over feature breadth.

---

## 2. Goals

- One window. Chat lives over the video, not in a separate window.
- Beautiful, considered visual design (Cozy default theme, 3 presets total).
- No regression vs. existing Syncplay capabilities (sync timestamps, play/pause state, chat, file-match check).
- Small, delightful extras that make co-watching feel warm.
- Works on Windows desktop. Cross-platform builds free from Flutter, not actively tested.

## 3. Non-goals (v1)

- Voice chat.
- Subtitle track sync between users (each user manages their own subs locally).
- Bookmark / clip sharing.
- Auto-pause on idle.
- Reply threads, avatars, stickers, URL link preview, slash commands.
- Streaming from URL (drag a video link). Future consideration.
- Hosting our own Syncplay server. We use public servers.

---

## 4. Stack

| Layer | Choice | Notes |
|---|---|---|
| App framework | Flutter desktop (stable channel) | Chosen for polish per effort, animations, theming |
| Video playback | `media_kit` package (Dart wrapper over libmpv) | Battle-tested libmpv binding for Flutter |
| Sync protocol | Custom Dart client of Syncplay text protocol | Documented at github.com/Syncplay/syncplay; protocol is line-based JSON over TCP/TLS |
| Local storage | SQLite via `drift` package | Saved rooms, watch history, settings |
| Build target | Windows x64 (primary), MSIX installer | macOS/Linux builds achievable but untested |

Server side: existing public Syncplay servers (`syncplay.pl:8999`, etc.). No new server infrastructure.

---

## 5. Architecture

Three internal cores. Each has a clear public interface; internals can change without affecting the others.

```
+--------------------------------------------------------------+
|                       UI Shell (Flutter)                      |
|  ConnectScreen | VideoSurface | ChatOverlay | ControlBar     |
|  PipWindow     | IdleMascot   | ReactionsLayer | Settings    |
+----------------------+--------------------+------------------+
                       |                    |
              +--------v------+   +---------v---------+
              |  Video Core   |   |    Sync Core      |
              |  (media_kit)  |   |  (Syncplay proto) |
              +---------------+   +---------+---------+
                                            |
                                  +---------v---------+
                                  | Syncplay server   |
                                  | (public, TCP/TLS) |
                                  +-------------------+
```

### 5.1 Video Core

Wraps libmpv via `media_kit`.

**Public interface:**
- `load(filePath)`
- `play()`, `pause()`, `togglePlay()`
- `seek(position)`
- `position` stream (current playback time)
- `state` stream (playing | paused | buffering | ended)
- `duration`
- `subtitleTracks`, `setSubtitle(id)`
- `audioTracks`, `setAudio(id)`
- `volume`, `setVolume(v)`

### 5.2 Sync Core

Speaks Syncplay's text protocol directly. Reference implementation: `syncplay/client.py` in upstream Syncplay repo.

**Public interface:**
- `connect(server, port, username, room, password?)`
- `disconnect()`
- `announceFile(name, size, duration)`
- `sendState(position, paused, doSeek)` — called when local user pauses/seeks
- `sendChat(text)`
- `sendCustomEvent(type, payload)` — for reactions; uses chat msg with prefix `__meow__:`
- Streams:
  - `peerState` (remote position + paused state)
  - `chatMessages`
  - `presence` (user join/leave)
  - `fileMismatch` (peer's file announce differs)
  - `connectionState` (connected | disconnected | error)

**Protocol details handled:**
- Hello / version handshake
- TLS upgrade (most public servers require it)
- Heartbeat / clock-drift compensation
- File announce + hash/size match
- "Ready" state propagation
- Chat messages (and our custom-event hack via chat prefix)

### 5.3 UI Shell

Flutter widget tree, themed by current preset. Connects video core ↔ sync core via reactive bindings:

- Local play/pause → video core → sync core sends state
- Sync core peer state → video core seeks/pauses to match
- Sync core chat → ChatOverlay
- Reactions emoji button → ReactionsLayer plays animation locally immediately; sync core sends custom event; peer's app plays the same animation on receive

---

## 6. Window & Layout

Single resizable window. Video fills the window. UI elements layer on top.

**Chat overlay:**
- Floating glass card. Default position: bottom-left, ~30% of window width, height auto from content (max 50%).
- Translucent background, theme-tinted, `backdrop-filter: blur`.
- Header strip with drag handle, peek-tab toggle, settings icon.
- Message list (newest at bottom), input field with emoji button + reaction emoji button + send.

**Drag behavior:**
- Click+hold header → drag mode.
- 4 corner snap zones light up. Releases snap to nearest if within threshold.
- Right-edge dock zone (vertical strip) snaps to collapse: chat becomes a 14px peek tab at right edge, vertically centered.
- Click peek tab → expand back to last position.
- Hotkey: `Tab` toggles collapse/expand.
- New message while collapsed: tab pulses, message peeks for 2 seconds, then re-collapses.

---

## 7. Themes

Three presets, switchable from settings:

| Preset | Vibe | Default? |
|---|---|---|
| Cozy | Warm dark (#1a1410), cream text, amber accent (#d4a574). Soft, fireplace. | **Yes** |
| Cinema Noir | Pure black, gold accent (#d4af37), serif italic for titles | No |
| Glass Aurora | Violet→cyan gradient, frosted glass chat | No |

Each theme defines: background tint, chat-card surface, accent color, text color, control bar fill, mascot palette.

---

## 8. Chat Features

- **Emoji picker** — popover above input field (use any small emoji set, e.g. Twemoji subset).
- **Reactions on messages** — hover any message → small reaction bar appears (heart, laugh, fire, cry, eyes). Click to react. Reactions sent via custom-event channel and appear under the original message as small clustered emoji.
- **Typing indicator** — when peer typing, three-dot animation appears at bottom of chat. Implemented via custom event sent on input change (debounced 1s).
- **Presence** — when peer joins or leaves, inline soft notice ("Lin joined the room") rendered in chat list, dim color, no avatar.
- **Timestamps** — small dim time under each message (e.g. "21:43"). Hover shows full date.

---

## 9. Player Controls

Auto-hide bar overlaid at bottom of video.

**Visible:** play/pause button, scrubber (position + buffered), elapsed / total time, subtitle toggle, audio track menu, settings cog (theme switch + advanced).

**Hidden by default, shows on:** mouse move, focus on bar. Idle 3 seconds → fades out.

**Keyboard:**
- `Space` — toggle play/pause
- `←` / `→` — seek -5s / +5s
- `Shift + ←` / `→` — seek -1min / +1min
- `↑` / `↓` — volume +/-
- `M` — mute toggle
- `F` — fullscreen toggle
- `Tab` — toggle chat collapse
- `Esc` — exit fullscreen / close PiP

**Drag-and-drop:** dropping a video file anywhere in the window loads it.

---

## 10. Connect Flow

**Launch screen:**
- Cozy-themed full-window panel.
- App title + greeting (uses last-used username, falls back to "Friend").
- **Profile list** (saved rooms): cards showing room name, server, username. Last-used at top, marked with green dot.
- **Big primary button:** "Start new room" — generates room code (e.g. `cozy-fox-42` via animal-adjective wordlist), uses default public server, copies code to clipboard, joins.
- **Secondary input:** "Enter code from friend" — paste code, joins same server + room.
- **Collapsible "Advanced":** custom server URL, port, room name, username, password. Used to create or join non-default rooms.

**On successful connect:** transition to video surface, chat overlay slides in.

**No video loaded state:** dimmed video area with a centered "Drop a video file to start" prompt and a "Browse…" button.

---

## 11. Extras

### 11.1 Floating reactions over video
Emoji button in chat input bar (separate from message-emoji). Tap → small emoji floats up from bottom-center of video, rises ~300px, fades. Custom event sent to peer; their app plays the same animation. Throttled to 1 per 500ms per user.

### 11.2 Picture-in-Picture
Window button on control bar → resizes window to ~400×225, sets always-on-top, hides chat panel except for 1-line ticker at bottom of PiP showing latest message (auto-fade after 4s). Click PiP body → restore.

Windows implementation: `WindowsManager.setAlwaysOnTop(true)` via `window_manager` package + custom resize.

### 11.3 Auto-pause on disconnect
When sync core emits `presence: left` for peer, video core pauses. Toast: "Lin disconnected — paused". On rejoin → toast "Lin reconnected", does NOT auto-resume (user chooses).

### 11.4 File mismatch helper
On peer file announce, if local loaded file's name OR size differs by > 5%, show modal:
> Lin is playing `<their_filename>` (1.24 GB)
> You have `<your_filename>` (1.40 GB)
> Likely the same? [Continue anyway] [Cancel]

If no local file loaded yet, show as inline banner instead: "Lin's playing `<filename>` — drop a matching file to sync."

### 11.5 Watch history
Per profile, persist (in SQLite): file path, file name, last position, duration, played-at timestamp. Recent items list visible from profile card menu and as a small section on connect screen ("Continue watching with Lin?"). Click → re-open file + seek to last position + announce.

### 11.6 Idle mascot
Small SVG fox in bottom corner of chat panel. Animates (slow breath, occasional ear-twitch) while video is paused or before either user starts playback. Fades out when video plays. Theme-aware (fox tints to accent color).

---

## 12. Custom Events (over Syncplay chat channel)

Syncplay has no rich-event API; we piggyback on chat messages with a prefix.

Format: chat message starting with the sentinel `__meow__:` is intercepted by both clients and not rendered as chat text. Payload after the sentinel is JSON.

Event types:
- `typing` — `{}` — sent on input keystroke, debounced 1s
- `reaction_msg` — `{msgId, emoji}` — reaction on a chat message
- `reaction_float` — `{emoji}` — floating emoji over video
- `presence_intent` — `{intent: 'afk' | 'back'}` — future use

Other clients without MeowWatch (e.g. plain Syncplay user) will see the sentinel as a weird chat line. Acceptable since target users are both running MeowWatch.

---

## 13. Storage

SQLite database at `%APPDATA%/MeowWatch/meowwatch.db`.

**Tables:**
- `profiles` — id, name, server, port, room, username, password (encrypted via OS keystore), is_default, last_used_at, theme_override
- `history` — id, profile_id, file_path, file_name, file_size, duration, last_position, played_at
- `settings` — key, value (theme, default username, hotkey overrides, window position)

---

## 14. Error Handling

- **Connection failure** — banner on connect screen with retry; profile not marked as failed (transient).
- **TLS / version mismatch** — clear error: "This server requires Syncplay v1.7+, please update MeowWatch."
- **File load failure** (codec missing, unreadable) — toast + suggestion: "media_kit / libmpv error: <code>. File may be unsupported."
- **Peer protocol errors** — logged, surfaced as toast if user-actionable; silent retry for transient.
- **Mid-session disconnect** — video pauses, banner "Reconnecting…" with countdown, auto-retry 5 times with backoff, then "Disconnected — [Reconnect] [Leave]".

All errors logged to `%APPDATA%/MeowWatch/logs/<date>.log` (rotated daily, 7-day retention).

---

## 15. Testing

- **Sync core unit tests** — protocol parser/encoder, state-diff calculation, drift correction, custom-event encode/decode. Target 80% coverage.
- **Chat parsing tests** — custom-event detection, emoji rendering, timestamp formatting.
- **Storage tests** — profile CRUD, history queries.
- **Manual E2E** — run two app instances on dev machine, exercise: connect, file load, mismatch modal, play/pause sync, chat, reactions, typing, disconnect/reconnect, PiP, drag-snap-collapse.
- **No automated UI tests** — too brittle for personal-toy scope.

---

## 16. Risks & Open Questions

| Risk | Mitigation |
|---|---|
| `media_kit` PiP on Windows may need extra plumbing (always-on-top, native resize) | Use `window_manager` package; verify on day-1 spike before deep building |
| libmpv DLL bundling/code-signing for Windows | Bundle prebuilt libmpv from media_kit; signing optional for personal use |
| Reaction over chat-channel hack may bloat chat history on server | Throttle aggressively, keep payloads tiny, accept minor weirdness |
| Custom emoji set licensing | Use Twemoji (CC-BY 4.0 with attribution) or system emoji |
| Syncplay protocol stability | Pin to v1.7 behavior; protocol has been stable for years |

---

## 17. Out-of-spec future ideas

- URL streaming (drop a YouTube / direct link → both fetch from URL).
- Voice chat (WebRTC).
- Watch parties of 3+ (Syncplay supports it; UI shifts non-trivially).
- Mobile companion app.
- Subtitle sync as opt-in.

---

## 18. Naming

Working name: **MeowWatch**. Repo: `D:\Repos\MeowWatch`. Re-namable if user dislikes.
