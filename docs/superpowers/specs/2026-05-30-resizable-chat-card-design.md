# Resizable Chat Card — Design Spec

**Date:** 2026-05-30
**Ships in:** v0.1.1-alpha
**Status:** Approved (design)

## Summary

The floating chat card currently renders at a hardcoded size — 30% of window
width by 50% of window height ([chat_overlay.dart:237](../../../lib/ui/chat/chat_overlay.dart)).
This feature lets the user resize the card by dragging a grip, reset it to the
default with one click, and have the chosen size persist across app launches.

## Goals

- Drag a resize grip to set the card's width and height **independently** (free
  resize, not aspect-locked).
- A **Reset** button on the card restores the default size (keeps the current
  corner; does not re-dock).
- The resized dimensions are **saved locally** and re-applied automatically on
  the next launch.

## Non-goals

- No per-corner remembered sizes (one size, shared across all four corners).
- No resize of the collapsed peek tab (only the open card resizes).
- No window-position/size persistence (out of scope; handled by `window_manager`
  elsewhere if at all).

## User-facing behavior

- **Resize grip:** a small handle at the card's **bottom-right corner** (the
  familiar resize affordance, clear of the header controls at the top). While
  the grip is being dragged, the card free-floats with its **top-left pinned**,
  so the corner under the cursor grows naturally to the right and down. On
  release, the card eases back to whichever corner it is docked in (reusing the
  existing post-drag snap-glide), now at the new size. This avoids any overlap
  with the header's drag area / collapse chevron / reset button, which all sit
  along the top edge.
- **Bounds (clamp):** the card cannot be dragged smaller than a usable minimum
  or larger than the window:
  - Min: 240 px wide × 220 px tall.
  - Max: 70% of window width × 85% of window height.
  - Values that would exceed these are clamped, so the grip "sticks" at the
    limit rather than letting the card become unusable or overflow offscreen.
- **Reset button:** a small icon in the card header row, placed left of the
  collapse chevron. One tap restores the default size (30% width × 50% height).
  The card keeps whichever corner it is docked in.
- **Persistence:** the chosen size survives quitting and relaunching the app.

## Architecture

Follows the existing **commands-in / pure-logic-split / immutable-state**
patterns already used by the chat overlay.

### 1. Pure resize math — `lib/ui/chat/resize_math.dart`

A headless, widget-free function mirroring the style of `chat_corner.dart`'s
`computeSnap`:

```
Size computeResize({
  required Size startSize,    // px, the card's size at grip-drag start
  required Offset dragDelta,  // px, accumulated grip movement from start
  required Size windowSize,   // px, for max-bound calculation
});
```

- Bottom-right grip: `+dx` grows width, `+dy` grows height. No per-corner sign
  logic — the card free-floats top-left-pinned during the drag, so growth is
  always right/down regardless of docked corner.
- Clamps the result to the min/max bounds above and returns the new `Size` in px.

Min/max constants live here as named consts so the math and any UI hints share
one source of truth:
`kMinCardWidth = 240`, `kMinCardHeight = 220`,
`kMaxCardWidthFrac = 0.70`, `kMaxCardHeightFrac = 0.85`.

### 2. Immutable layout state — extend `ChatOverlayLayout`

Add two nullable fraction fields (null = use default):

```
final double? widthFrac;   // 0..1 fraction of window width
final double? heightFrac;  // 0..1 fraction of window height
```

- `copyWith` gains both fields.
- New `applyResize(Size newPx, Size windowPx)` → returns a copy with
  `widthFrac`/`heightFrac` derived from the px size ÷ window size.
- New `resetSize()` → returns a copy with both fraction fields cleared (back to
  default).
- `==`/`hashCode` updated to include the new fields.

**Why fractions, not pixels:** storing a fraction of the window keeps the card
proportional if the window is later resized or the app opens on a different
display, avoiding a card that overflows or shrinks to a sliver. The card's px
size is computed at render time as `frac * windowSize`, falling back to the
0.30 / 0.50 defaults when the fraction is null.

### 3. Persistence — reuse `SettingsStore`

- New key constant: `kChatCardSizeSettingKey = 'chat_card_size'`.
- Stored value format: `"<widthFrac>,<heightFrac>"` (e.g. `"0.42,0.63"`).
- **Load:** at startup (where the theme setting is already read), HomeScreen
  reads the key, parses the two doubles, and seeds the initial
  `ChatOverlayLayout` with them. Malformed/missing value → defaults.
- **Save:** HomeScreen writes the key when a resize gesture ends and when reset
  is tapped. A resize is a single discrete commit on drag-end (not per-frame),
  so no debounce machinery is needed.

### 4. Widget wiring — `chat_overlay.dart`

- `ChatOverlay` gains callbacks `onResize(Size newPx)` and `onResetSize`,
  parallel to the existing `onSnap` / `onToggleCollapsed`.
- The card's render size is computed from `widget.widthFrac`/`heightFrac` (passed
  down from the parent state) instead of the hardcoded `0.3 / 0.5` literals.
- `_GlassCard` gains:
  - A resize grip widget (a `GestureDetector` with `onPanStart/Update/End`)
    positioned at the free corner. During the gesture it accumulates delta,
    feeds `computeResize`, and live-updates the rendered size; on end it reports
    the final size via `onResize`.
  - A reset `IconButton`/`GestureDetector` in the header row (left of the
    chevron) calling `onResetSize`.
- The free-corner position is derived from the docked `corner` (a small switch,
  same shape as `_alignmentFor`).

## Data flow

```
grip drag → _GlassCard accumulates delta → computeResize(clamped px)
          → live setState (card re-renders at new px)
grip end  → onResize(finalPx) → HomeScreen: layout.applyResize(px, window)
          → SettingsStore.set('chat_card_size', "wFrac,hFrac")
reset tap → onResetSize → HomeScreen: layout.resetSize()
          → SettingsStore.set('chat_card_size', "")  // empty = defaults on load
startup   → SettingsStore.get('chat_card_size') → parse → seed ChatOverlayLayout
```

## Error handling

- Parsing the stored value is defensive: any parse failure, out-of-range
  fraction, or missing key falls back to the defaults (never throws into the UI).
- `computeResize` always returns a clamped, valid size — callers cannot produce
  an invalid card.

## Testing (TDD)

- **`resize_math.dart`** — unit tests: delta→size for each docked corner (sign
  handling), min clamp, max clamp, exact-bound cases. Headless, no widget pump.
- **`ChatOverlayLayout`** — unit tests: `applyResize` fraction derivation,
  `resetSize` clears fields, `copyWith`/equality with new fields.
- **Persistence round-trip** — fake `SettingsStore`: save then load reproduces
  the same fractions; malformed value → defaults.
- **Widget test** — grip drag changes rendered card size; reset button restores
  default; uses a fake store.
- **Goldens** — if the header layout (new reset icon) or grip shifts the card's
  appearance, regenerate `test/ui/chat/goldens/*.png` with `--update-goldens`
  and visually inspect before committing.

## Files touched

| File | Change |
|------|--------|
| `lib/ui/chat/resize_math.dart` | **new** — pure resize+clamp logic |
| `lib/ui/chat/chat_overlay_layout.dart` | add size fractions + `applyResize`/`resetSize` |
| `lib/ui/chat/chat_overlay.dart` | grip + reset button; size from fractions |
| `lib/core/data/settings_store.dart` | add `kChatCardSizeSettingKey` |
| `lib/ui/home_screen.dart` | load/seed/save card size via `SettingsStore` |
| `lib/core/app_version.dart` + `pubspec.yaml` | bump to `0.1.1-alpha` |
| `test/ui/chat/resize_math_test.dart` | **new** |
| `test/ui/chat/chat_overlay_layout_test.dart` | extend |
| `docs/ROADMAP.md` | note the feature under the relevant phase |

## Open risks

- **Free-corner grip vs. header drag overlap:** the grip sits at the opposite
  corner from the header's drag area, so they don't conflict. Verify the grip
  hit target (~18–22 px) doesn't eat into the message list scroll area.
- **Two-instance manual test:** confirm resize + reset + persistence works in a
  real Release build (per CLAUDE.md, test Release not Debug), and that a resized
  card still drags/snaps/collapses correctly.
