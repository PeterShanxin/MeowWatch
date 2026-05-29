# MeowWatch Roadmap

Six phases. Each phase ends with working, shippable software. One plan per phase.

| Phase | Name | Deliverable | Plan |
|---|---|---|---|
| 1 ✅ | Foundation | **Shipped (tag `phase-1-complete`).** Drag-drop or Browse → plays via libmpv. Keyboard (space, ←→, ↑↓). Bonus polish landed early: auto-hiding control bar + scrubber, play/pause center flash, held-seek pill (marching chevrons + accumulated time), volume level indicator, click-to-pause, double-click fullscreen (`window_manager`). | [2026-05-28-phase-1-foundation.md](superpowers/plans/2026-05-28-phase-1-foundation.md) |
| 2 ✅ | Sync core | **Shipped (tag `phase-2-complete`).** Custom Dart Syncplay client: TCP+startTLS, Hello handshake, State heartbeat, `ignoringOnTheFly` + `setBy`/compare-to-local convergence (no fighting), one-directional rewind, presence via Set/List roster. Two instances sync play/pause/seek through a public server. Temp dev connect bar + status hints. Chat receive plumbed (no UI). | [2026-05-28-phase-2-sync-core.md](superpowers/plans/2026-05-28-phase-2-sync-core.md) |
| 3 ✅ | Chat overlay | **Shipped (tag `phase-3-complete`).** Glass-card chat overlay floating over video: grab-header drag (seeds from real card rect — no first-grab jump), snap to all 4 corners, drop-on-right-edge-middle collapse to a centerRight peek tab (pulses on new msg). Tab hotkey toggle. Text chat over Syncplay chat channel (server-echo model, no optimistic insert), sender-name label on friend bubbles + HH:MM timestamps. Cozy theme hardcoded. | [2026-05-28-phase-3-chat-overlay.md](superpowers/plans/2026-05-28-phase-3-chat-overlay.md) |
| 4 | Connect flow + profiles | Connect screen with saved profile cards + "Start new room" auto room-code + "Enter code" field + Advanced collapsible. SQLite via `drift`. | _TBD_ |
| 5 | Themes | Three preset themes: Cozy (default), Cinema Noir, Glass Aurora. Switcher in settings. Applied to chat overlay, controls, connect screen. | _TBD_ |
| 6 | Extras | Floating reactions, PiP, auto-pause on disconnect, file-mismatch helper, watch history, idle mascot, msg reactions, typing indicator, presence, timestamps. | _TBD_ |

## Design spec

[superpowers/specs/2026-05-28-meowwatch-design.md](superpowers/specs/2026-05-28-meowwatch-design.md) — full design covering all six phases.

## Backlog / future tuning

- **Sync activity notifications** — surface play/pause/seek-forward/seek-back events (who did what) as a transient toast on the chat card or over the video, so each peer sees why playback jumped. (Requested Phase 3; fits Phase 6 extras.)
- **Seek-collision smoothing** — when both peers seek near-simultaneously (or during an RTT spike), positions briefly fight before converging. Add debounce / "syncing…" indicator to smooth the transition. (Observed Phase 2; not blocking.)
- **Streaming from URL** — drop a video link instead of a local file. (Also listed out-of-v1 below.)

## Out of v1 scope

- Voice chat
- Subtitle track sync between users
- Bookmark / clip sharing
- Auto-pause on idle
- Reply threads, avatars, stickers, URL link preview, slash commands
- Streaming from URL (drop a video link)
- Hosting our own Syncplay server (we use public servers)
