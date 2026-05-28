# Phase 3 — Chat Overlay Design

Slice of the master design (`2026-05-28-meowwatch-design.md` §6, §8, §12) scoped for Phase 3. Captures the scope line and architecture decided in brainstorming.

## Scope

**In:**
- Floating glass chat card over the video.
- Drag by header → snap to nearest of 4 corners; drag to right edge → collapse to a 14px peek tab.
- Peek tab click and `Tab` key both toggle collapse/expand.
- New message while collapsed → tab pulses, message peeks ~2s, then re-collapses.
- Basic text chat: send + receive, message list (newest at bottom), own messages right / friend left.
- Per-message timestamp (small, dim).
- Cozy theme hardcoded (warm dark `#1a1410`, amber `#d4a574`, cream `#f5e6d3`, backdrop blur).

**Deferred to Phase 6:** emoji picker, message reactions, typing indicator, idle mascot.
**Deferred to Phase 5:** theme switching (Cozy is hardcoded for now).
**Explicitly out of Phase 3:** inline join/leave presence notices in the chat list (kept in Phase 6 with other chat extras).

## Architecture (approach A — logic split from view)

Pure, testable logic separated from drawing — same ethos as Phase 2's `decideFollow`.

### Position brain — `lib/ui/chat/chat_overlay_layout.dart`
- Immutable `ChatOverlayLayout` { `corner` (which of 4), `collapsed` (bool), `lastCorner` (corner to restore to) }.
- Pure `computeSnap({required Offset dropTopLeft, required Size cardSize, required Size windowSize, double edgeDockZone, double cornerThreshold})` → result describing: snap to a named corner, or dock-collapse.
- `ChatCorner` enum: topLeft, topRight, bottomLeft, bottomRight.
- Snap rule: if drop point is within `edgeDockZone` of the right edge → collapse. Else snap to nearest corner.
- No Flutter widget imports beyond `dart:ui`/`Offset`/`Size` — unit-testable headless.

### Chat store — `lib/core/chat/chat_store.dart`
- Holds immutable `List<ChatMessage>` (append-only, new copy on add — no mutation).
- Subscribes to `SyncCore.chat` stream; on each message, stamps `timestamp = DateTime.now()` and appends.
- Exposes a broadcast `Stream<List<ChatMessage>>` (or `ValueListenable`) for the view.
- `sendChat(text)` delegates to `SyncCore.sendChat`; the server echoes it back on the chat stream, so it lands in the list via the same receive path (single source of truth — no optimistic local insert, no double render).
- Owns its stream subscription; `dispose()` cancels it.

### View widgets (`lib/ui/chat/`)
- `chat_overlay.dart` — the glass card. `Positioned` in HomeScreen's Stack at the corner from layout state. Header is the drag handle (`onPanUpdate` moves a free position; `onPanEnd` runs `computeSnap`). Holds message list + input. Collapsed state swaps card for `PeekTab`.
- `chat_bubble.dart` — one message: mine (compare `username` to our username) right-aligned amber-tinted, friend left-aligned; dim timestamp beneath.
- `chat_input.dart` — text field + send button; submit on Enter and on button. Clears after send.
- `peek_tab.dart` — 14px tab at right edge, vertically centered; pulse animation; tap to expand.

### Data type change — `lib/core/sync/peer_state.dart`
- Add `final DateTime? timestamp;` to `ChatMessage` (nullable; set by the store on arrival, not by the decoder). Update `==`/`hashCode`.

### Wiring — `lib/ui/home_screen.dart`
- Construct `ChatStore(sync: _sync)` alongside the existing cores; dispose it.
- Add `ChatOverlay` to the video Stack (above `VideoSurface`, below the sync hint banner).
- `Tab` key toggles collapse/expand (in addition to peek-tab tap).

## Defaults / constants
- Default corner: bottomLeft. Card width ≈ 30% of window, max height ≈ 50%.
- `edgeDockZone` and `cornerThreshold`: concrete px values fixed in the plan (e.g. 48px edge zone).
- Peek tab width: 14px. New-message peek duration: 2s.

## Testing
- **Snap math** — unit tests: each corner from representative drop points; edge-dock when within zone; restore corner after expand.
- **Chat store** — unit tests with a fake SyncCore: append on receive, timestamp set, order preserved, mine-vs-friend distinction via username.
- **Widgets** — `chat_bubble` alignment (mine right / friend left, timestamp shown); `chat_input` send clears field + calls store; `peek_tab` tap fires expand.
- **Manual E2E** — two app instances: send both directions, drag + corner snap, edge-collapse + peek, `Tab` toggle, new-message pulse while collapsed.

## Custom-event note
The `__meow__:` sentinel (master spec §12) is a Phase 6 concern. Phase 3 sends no sentinel traffic. A one-line defensive filter (drop messages starting with `__meow__:` from the visible list) is optional and may be added with reactions in Phase 6.
