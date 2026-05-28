# MeowWatch Roadmap

Six phases. Each phase ends with working, shippable software. One plan per phase.

| Phase | Name | Deliverable | Plan |
|---|---|---|---|
| 1 ✅ | Foundation | **Shipped (tag `phase-1-complete`).** Drag-drop or Browse → plays via libmpv. Keyboard (space, ←→, ↑↓). Bonus polish landed early: auto-hiding control bar + scrubber, play/pause center flash, held-seek pill (marching chevrons + accumulated time), volume level indicator, click-to-pause, double-click fullscreen (`window_manager`). | [2026-05-28-phase-1-foundation.md](superpowers/plans/2026-05-28-phase-1-foundation.md) |
| 2 | Sync core | Custom Dart client for Syncplay text protocol. Two app instances on same room sync play/pause/seek. No chat UI yet. | _next — ready to plan_ |
| 3 | Chat overlay | Glass-card chat overlay: drag, snap to corners, drop-on-edge collapse to peek tab. Hotkey toggle. Basic text chat over Syncplay chat channel. | _TBD_ |
| 4 | Connect flow + profiles | Connect screen with saved profile cards + "Start new room" auto room-code + "Enter code" field + Advanced collapsible. SQLite via `drift`. | _TBD_ |
| 5 | Themes | Three preset themes: Cozy (default), Cinema Noir, Glass Aurora. Switcher in settings. Applied to chat overlay, controls, connect screen. | _TBD_ |
| 6 | Extras | Floating reactions, PiP, auto-pause on disconnect, file-mismatch helper, watch history, idle mascot, msg reactions, typing indicator, presence, timestamps. | _TBD_ |

## Design spec

[superpowers/specs/2026-05-28-meowwatch-design.md](superpowers/specs/2026-05-28-meowwatch-design.md) — full design covering all six phases.

## Out of v1 scope

- Voice chat
- Subtitle track sync between users
- Bookmark / clip sharing
- Auto-pause on idle
- Reply threads, avatars, stickers, URL link preview, slash commands
- Streaming from URL (drop a video link)
- Hosting our own Syncplay server (we use public servers)
