# Four-Corner Resize + Multi-Version Changelog — Design Spec

**Date:** 2026-05-30
**Ships in:** v0.1.2-alpha
**Status:** Approved (design)
**Branch:** `feat/resizable-chat-card` (continues the resize work)

Builds on [2026-05-30-resizable-chat-card-design.md](2026-05-30-resizable-chat-card-design.md).
This is the feedback round after manual testing: height resize was broken,
resize wanted from all four corners, buttons need tooltips, and the updater
should show a scrollable changelog spanning every version between the installed
build and the latest.

## Feature A — Four-corner resize, fixed height, tooltips

### A1. Fixed-height card (fixes "height won't resize")

**Problem:** `_GlassCard` renders `Container(width: ..., constraints: BoxConstraints(maxHeight: ...))` around a `Column(mainAxisSize: MainAxisSize.min, ...)`. The card hugs its content, so when there are few messages, increasing the height cap changes nothing visible — height appears un-resizable.

**Fix:** give the card a **fixed height** and let the message list fill it.
- `Container(width: width, height: height, ...)`.
- The message area becomes `Expanded` (instead of `Flexible` + `shrinkWrap`), so it fills the fixed height and scrolls when content overflows.
- Empty space below the messages when few messages is expected and accepted.

**Side benefit:** the post-drag snap-glide uses the card's real height; with a fixed height that value is exact, so docking lands precisely.

### A2. Four-corner resize

Replace the single bottom-right grip with **one grip per corner** (top-left,
top-right, bottom-left, bottom-right). Dragging a grip resizes the card with the
**opposite corner pinned**: the card grows/shrinks toward the cursor, and its
top-left position shifts for grips on the top or left edges.

**Pure geometry — `lib/ui/chat/resize_math.dart`** (replaces `computeResize`):

```
({Offset topLeft, Size size}) computeCornerResize({
  required Offset startTopLeft, // card top-left at drag start (overlay-local px)
  required Size startSize,      // card size at drag start (px)
  required Offset dragDelta,    // accumulated grip movement from start (px)
  required ChatCorner grip,     // which corner is being dragged
  required Size windowSize,     // px, for max-bound clamping
});
```

Per-axis logic (the anchor is the corner opposite `grip`):
- **Horizontal.** Right-edge grips (topRight/bottomRight): `newWidth = startSize.width + dx`, left edge fixed → `newLeft = startTopLeft.dx`. Left-edge grips (topLeft/bottomLeft): the right edge is fixed at `rightEdge = startTopLeft.dx + startSize.width`; `newWidth = startSize.width - dx`; after clamping, `newLeft = rightEdge - newWidth` so the anchor truly stays put.
- **Vertical.** Bottom grips: `newHeight = startSize.height + dy`, top fixed → `newTop = startTopLeft.dy`. Top grips: bottom edge fixed at `bottomEdge = startTopLeft.dy + startSize.height`; `newHeight = startSize.height - dy`; after clamping, `newTop = bottomEdge - newHeight`.

Clamp width to `[kMinCardWidth, windowSize.width * kMaxCardWidthFrac]` and
height to `[kMinCardHeight, windowSize.height * kMaxCardHeightFrac]` (existing
constants: 240, 220, 0.70, 0.85). Position is always recomputed from the fixed
edge **after** the size is clamped, so the anchored corner never drifts.

Returns a record `(topLeft, size)`.

**Widget wiring — `chat_overlay.dart`:**
- `_GlassCard` renders four small grips, one per corner, as `Positioned`
  children of the card's `Stack`, **after** the `DecoratedBox` so they win
  hit-testing at the corners. Each grip is a `GestureDetector`
  (`onPanStart/Update/End`) that reports its own `ChatCorner`.
- `_ChatOverlayState` resize handlers take the grip corner:
  - `_startResize(ChatCorner grip)` captures `_resizeStartSize`, the start
    top-left (`_dragTopLeft`, already seeded from the real card rect), and
    `_overlaySize`; remembers `grip`.
  - `_updateResize(Offset delta)` accumulates delta, calls `computeCornerResize`,
    and sets **both** `_dragTopLeft` and `_dragCardSize` from the result, so the
    card free-floats correctly (top/left grips move the card).
  - `_endResize()` reports the final size via `onResize`, then glides back to the
    docked corner via the existing `_snapCtrl` (`_cornerTopLeft(widget.corner,
    size, window)`), exactly as today.
- The persisted size is still width/height **fractions** of the window
  (unchanged from the prior spec); only the px size is reported up. Position is
  transient (the card always re-docks to its corner), so only size persists.

**Header overlap:** the top two grips sit at the extreme top corners; the header's
reset and collapse icons are inset from the corners by their padding, and the
grips render on top, so each control stays independently hittable. Grips are
small (≈18 px hit target, 14 px icon).

### A3. Tooltips

Wrap each chat-card control in a `Tooltip` (hover-to-show on desktop):
- Drag handle (`Icons.drag_indicator`) → "Drag to move"
- Reset button (`Icons.crop_free`) → "Reset size"
- Collapse chevron (`Icons.chevron_right`) → "Hide chat"
- Each corner grip → "Drag to resize"

## Feature B — Multi-version changelog in the updater

### B1. Source of truth — `CHANGELOG.md`

A `CHANGELOG.md` at the repo root, newest version first, in a fixed format the
CI parser can read:

```
## [0.1.2-alpha] - 2026-05-30
- Four-corner resize for the chat card.
- Tooltips on chat-card buttons.
- Updater shows a scrollable multi-version changelog.

## [0.1.1-alpha] - 2026-05-30
- Resizable chat card (drag grip + reset), size persists locally.

## [0.1.0-alpha] - 2026-05-30
- Initial alpha: co-watch, sync, chat overlay, themes, auto-update.
```

Rules the parser relies on: each version header is `## [<version>] - <date>`;
body is every line until the next `## [` or end of file.

### B2. CI publishes `releases/changelog.json` to R2

A new step in the release job of `.github/workflows/build.yml` (after the
existing R2 upload). It parses `CHANGELOG.md` into a JSON array, newest first,
and uploads it to `r2:$BUCKET/releases/changelog.json`:

```json
[
  {"version": "0.1.2-alpha", "date": "2026-05-30", "notes": "- Four-corner resize…\n- Tooltips…"},
  {"version": "0.1.1-alpha", "date": "2026-05-30", "notes": "- Resizable chat card…"}
]
```

Parsing is done with a short Python snippet (Python is preinstalled on the
`ubuntu-latest` runner). The whole `CHANGELOG.md` is reparsed every release
(it contains all versions), so no read-back/accumulation from R2 is needed.

### B3. App — `UpdateService.fetchChangelog()`

```
Future<List<ChangelogEntry>> fetchChangelog();
```

- GETs `{baseUrl}/releases/changelog.json` (10 s timeout).
- Parses into `ChangelogEntry(version, date, notes)` (immutable).
- Returns only entries **newer than `appVersion`**, reusing the existing
  `_isNewer` semver compare, newest first.
- On any failure (404, network, parse) returns an **empty list** — never throws.

### B4. App — update dialog shows the scrollable list

In `update_dialog.dart`, the `updateAvailable` phase:
- After `checkForUpdate` succeeds with `updateAvailable`, also call
  `fetchChangelog()` and store the list.
- Replace today's single `releaseNotes` box (maxLines 6, ellipsis) with a
  **scrollable list** (a bounded-height `ListView`, e.g. `maxHeight: 220`): one
  block per newer version — a `v<version> · <date>` header followed by its
  notes. Multiple versions between the installed build and latest are all shown.
- **Fallback:** if `fetchChangelog()` returns empty (older bucket without
  `changelog.json`, or fetch failure), show the existing single
  `info.releaseNotes` box as before. Nothing regresses.
- The Download button is unchanged (downloads the latest asset from `latest.json`).

## Architecture / files

| File | Change |
|------|--------|
| `lib/ui/chat/resize_math.dart` | replace `computeResize` with `computeCornerResize` returning `(topLeft, size)` |
| `lib/ui/chat/chat_overlay.dart` | fixed height + `Expanded` message list; 4 corner grips; grip-corner-aware resize handlers; tooltips |
| `lib/core/update/update_service.dart` | add `ChangelogEntry` + `fetchChangelog()` |
| `lib/ui/update_dialog.dart` | scrollable multi-version changelog list + fallback |
| `.github/workflows/build.yml` | new step: parse `CHANGELOG.md` → upload `changelog.json` to R2 |
| `CHANGELOG.md` | **new** — version history (source of truth) |
| `lib/core/app_version.dart`, `pubspec.yaml` | bump to `0.1.2-alpha` |
| `test/ui/chat/resize_math_test.dart` | rewrite for `computeCornerResize` (all 4 corners + clamps) |
| `test/ui/chat/chat_overlay_resize_test.dart` | extend: a grip per corner; tooltips present |
| `test/core/update/changelog_test.dart` | **new** — changelog parse/filter |

## Error handling

- `computeCornerResize` always returns a clamped, valid `(topLeft, size)`; the
  anchored corner is recomputed from the fixed edge after clamping so it cannot
  drift off under aggressive drags.
- `fetchChangelog` is fully defensive (empty list on any failure); the dialog
  falls back to the single-note view.
- The CI parser tolerates a missing/empty `CHANGELOG.md` by writing `[]`.

## Testing (TDD)

- **`computeCornerResize`** — for each of the 4 grips: grow, shrink, min clamp,
  max clamp, and that the anchored (opposite) corner stays fixed (assert on the
  returned `topLeft` + `size`).
- **`ChangelogEntry` / `fetchChangelog`** — parse a sample `changelog.json`;
  filter drops versions ≤ installed; malformed JSON → empty list. Use an
  injectable base URL / fake HTTP client (the service already takes `baseUrl`).
- **Widget** — four grips present (one per corner, each keyed); dragging each
  reports a size; reset still works; tooltips attached (find `Tooltip` by
  message). Regenerate chat goldens if the header/grip visuals shift, inspect
  before committing.
- **Manual (Release build, per CLAUDE.md):** resize from every corner (incl.
  height), confirm opposite corner stays put and the card re-docks; hover shows
  tooltips; with a 0.1.1 build installed, the 0.1.2 release shows a changelog
  listing 0.1.2 (and any other newer versions), scrollable.

## Non-goals

- No per-corner remembered sizes (one size, all corners; unchanged).
- No live position persistence (card always re-docks to its corner).
- No rich markdown rendering of notes (plain text lines).
- Download path stays on `latest.json`; `changelog.json` is display-only.
