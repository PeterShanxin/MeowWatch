# MeowWatch Roadmap

Six phases. Each phase ends with working, shippable software. One plan per phase.

| Phase | Name | Deliverable | Plan |
|---|---|---|---|
| 1 ✅ | Foundation | **Shipped (tag `phase-1-complete`).** Drag-drop or Browse → plays via libmpv. Keyboard (space, ←→, ↑↓). Bonus polish landed early: auto-hiding control bar + scrubber, play/pause center flash, held-seek pill (marching chevrons + accumulated time), volume level indicator, click-to-pause, double-click fullscreen (`window_manager`). | [2026-05-28-phase-1-foundation.md](superpowers/plans/2026-05-28-phase-1-foundation.md) |
| 2 ✅ | Sync core | **Shipped (tag `phase-2-complete`).** Custom Dart Syncplay client: TCP+startTLS, Hello handshake, State heartbeat, `ignoringOnTheFly` + `setBy`/compare-to-local convergence (no fighting), one-directional rewind, presence via Set/List roster. Two instances sync play/pause/seek through a public server. Temp dev connect bar + status hints. Chat receive plumbed (no UI). | [2026-05-28-phase-2-sync-core.md](superpowers/plans/2026-05-28-phase-2-sync-core.md) |
| 3 ✅ | Chat overlay | **Shipped (tag `phase-3-complete`).** Glass-card chat overlay floating over video: grab-header drag (seeds from real card rect — no first-grab jump), snap to all 4 corners, drop-on-right-edge-middle collapse to a centerRight peek tab (pulses on new msg). Tab hotkey toggle. Text chat over Syncplay chat channel (server-echo model, no optimistic insert), sender-name label on friend bubbles + HH:MM timestamps. Cozy theme hardcoded. | [2026-05-28-phase-3-chat-overlay.md](superpowers/plans/2026-05-28-phase-3-chat-overlay.md) |
| 4 ✅ | Connect flow + profiles | **Shipped (tag `phase-4-complete`).** Connect screen: saved profile cards (auto-saved on every connect, deletable, most-recent dot), "Start new room" (auto room-code → clipboard), "Enter code from friend", Advanced collapsible (server/port/password — passwords stored plaintext by design), "Continue watching" history that resumes at last position. SQLite via `drift` (background isolate). On connect → HomeScreen with a small Leave button. Pinned `path_provider_android <2.3.0` to drop `jni` from the Windows build. | [2026-05-29-phase-4-connect-profiles.md](superpowers/plans/2026-05-29-phase-4-connect-profiles.md) |
| 5 ✅ | Themes | **Shipped (tag `phase-5-complete`).** All ~57 hardcoded Cozy literals extracted into a `ThemeExtension<MeowColors>`; 3 presets — Cozy (default), Cinema Noir, Glass Aurora (gradient + glass blur). Switcher swatches on the Connect screen and in-player via a top-left gear menu (anchored popover: swatches + Leave). Choice persists in SQLite (Settings k/v table, schema v1→v2 migration). `context.meow` getter; `themeDataFor(id)` cross-fades on swap. | [2026-05-29-phase-5-themes.md](superpowers/plans/2026-05-29-phase-5-themes.md) |
| 6 ✅ | Extras & polish | **Shipped (tag `phase-6-complete`).** Built one-at-a-time on `main`. **Sync/presence:** auto-pause on sync drop/friend-leave (2s debounce); friend joined/left banners + chat system lines; roster fix so a file-less joiner sees existing peers; status-aware connect banner ("Connecting to room X…"). **Room/file:** room code in player gear (copyable + snackbar) and connect-screen "copied" toast; **file-mismatch warning** (peer file from Set/List, byte-size-first compare). **Delight:** **idle cat mascot** (breathes + blinks); **chat control channel** (sentinel-prefixed reactions/typing); **floating reactions** (emoji burst + palette button); **typing indicator**. **Chat overlay polish:** animated dock-zone hints while dragging (4 quadrants + slim collapse bar), gear hides during drag, collapse/corner-dock glide, Tab toggles in one press (focus restored on every collapse/dock path), auto-focus input on open, larger peek/chevron hit targets. **Connect/history:** continue-watching is deletable + clear-all, rich subtitle (runtime / % / last-played / size) with a progress bar (duration backfilled once mpv probes it), and **room + name per entry** (history schema v2→v3); responsive two-column connect layout past 880px + controller-bound scrollbar. **Gear menu:** fade/slide entrance, full-width centered rows. **Debug:** always-on sync log. Already-done earlier: watch history (P4), presence + HH:MM timestamps (P3). **Deferred → future work** (see backlog): PiP, per-message reactions. | built incrementally on `main` |

## Design spec

[superpowers/specs/2026-05-28-meowwatch-design.md](superpowers/specs/2026-05-28-meowwatch-design.md) — full design covering all six phases.

## Future work

All six planned phases are shipped. The items below are out of the v1 plan — deferred extras, new ideas surfaced while building, and tuning notes — kept for a future iteration.

### Deferred from Phase 6 (with rationale)

- **Picture-in-Picture (always-on-top mini player)** — deferred. Flutter Windows has no built-in PiP; needs a second borderless always-on-top OS window (or a platform-channel/native-window approach) plus its own video surface. That's a self-contained mini-project, not a same-session extra — give it its own spec.
- **Per-message reactions** — deferred. The Syncplay chat channel carries no stable per-message ID, so "react to _that_ message" can't be addressed reliably across peers. Would need a local message-id scheme exchanged over the control channel (the sentinel channel from this phase is the right foundation). Floating reactions cover the quick-emoji urge for now.

### New ideas (surfaced while building Phase 6)

- **Mascot reacts to events** — the idle cat could wave/perk up when a friend joins, or nap when alone. Cheap delight; reuse the `IdleMascot` painter with extra poses.
- **Reaction keyboard shortcuts** — number keys / a hotkey fire the top emoji without opening the palette.
- **Soft chime on friend join/leave** — optional audio cue paired with the existing "🐾 X joined" banner.
- **"Friend is buffering" hint** — distinct from auto-pause: show when a peer stalls so you know to wait (needs a buffering signal over the control channel).

### Earlier tuning notes

- **Sync activity notifications** — surface play/pause/seek-forward/seek-back events (who did what) as a transient toast on the chat card or over the video, so each peer sees why playback jumped. (Requested Phase 3; the control channel + banner from Phase 6 make this straightforward now.)
- **Seek-collision smoothing** — when both peers seek near-simultaneously (or during an RTT spike), positions briefly fight before converging. Add debounce / "syncing…" indicator to smooth the transition. (Observed Phase 2; not blocking.)
- **Streaming from URL** — drop a video link instead of a local file. (Also listed out-of-v1 below.)

### Infrastructure & distribution

- **Windows ARM64 CI** — native ARM64 builds via `windows-11-arm` GitHub Actions runner. Blocked on: repo is private; ARM64 runners are free only for public repos (or available as paid larger runners). Unblock: make repo public or purchase larger runners.
- **Cloudflare R2 release hosting** — CI workflow has commented-out R2 upload steps ready to activate once the R2 bucket is provisioned and secrets (`R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`, `R2_PUBLIC_URL`) are configured in GitHub repo settings.
- **MSIX installer** — Windows Store distribution with system-managed updates. Requires a code-signing certificate.

### Feature requests backlog (split from umbrella request)

- **Windows ARM64 compatibility (native build + runtime verification)**
  - Ship a native ARM64 build artifact (not x64 emulation-only).
  - Verify two-instance local playback + sync behavior on ARM64 hardware.
  - Add release labeling so users can clearly choose x64 vs ARM64 packages.
- **Sync activity status messages (pause/seek feedback)**
  - Show transient, human-readable status lines for remote playback actions (example: "Video paused at 00:12:34", "Video skipped to 00:15:10").
  - Include actor context when available ("Alice paused…") and de-duplicate noisy repeats.
  - Keep messages non-blocking and auto-dismissed to avoid UI clutter.
- **Auto-hide minimized chat icon after idle**
  - When chat is minimized/collapsed, fade the icon/tab out after X seconds of no pointer/keyboard activity.
  - Restore visibility immediately on user interaction and on new unread chat activity.
  - Keep behavior optional or conservatively tuned to avoid discoverability regressions.
- **Resizable chat window**
  - Allow drag-resizing the expanded chat card with min/max constraints.
  - Preserve corner/edge docking behavior after resize and persist the chosen size.
  - Ensure responsive layout still works at small window sizes and high DPI scales.
- **Volume adjustment controls**
  - Provide explicit in-UI volume controls (slider and/or +/- actions) in addition to keyboard shortcuts.
  - Show current volume value and mute state clearly.
  - Keep Syncplay semantics local-only for volume (no remote volume synchronization).

## Out of v1 scope

- Voice chat
- Subtitle track sync between users
- Bookmark / clip sharing
- Auto-pause on idle
- Reply threads, avatars, stickers, URL link preview, slash commands
- Streaming from URL (drop a video link)
- Hosting our own Syncplay server (we use public servers)
