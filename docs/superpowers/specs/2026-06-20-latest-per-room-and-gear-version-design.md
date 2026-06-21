# Latest-per-room continue-watching + gear version access — design

**Date:** 2026-06-20
**Issue:** [#136](https://github.com/PeterShanxin/MeowWatch/issues/136)
**Type:** Enhancement (`feat:` → MINOR bump, 0.31.1-alpha → 0.32.0-alpha)

## Summary

Three bundled changes:

1. **#136** — "Continue watching" collapses to the latest video per room by
   default, with a Settings toggle to switch back to showing every video.
2. **Playroom gear** — add a version/updates footer line to the in-room gear
   (`PlayerMenuButton`), since no version badge exists inside a room.
3. **Lobby gear** — gets the new #136 toggle (the lobby already has a gear; no
   version row there — the bottom-right version badge already covers it).

## Decisions locked with the user

- **Collapse is hide-not-delete.** `latestPerRoom` filters older same-room
  entries out of the *view* only; rows stay in the database. Flipping the toggle
  to `everyVideo` brings them all back. Nothing is destroyed.
- **No version row in the lobby gear.** The version badge (bottom-right of the
  connect screen) already provides check-version / changelog / update there.
- **In-room version line placement:** a dim, tappable footer at the very bottom
  of the in-room gear, below "Leave room".

## Part 1 — Data layer (#136)

Pure, headless-testable logic, following the existing `sync_follow.dart` /
`chat_corner.dart` "pure logic split out from widgets" pattern.

### `HistoryMode`

New `enum HistoryMode { latestPerRoom, everyVideo }` (new file
`lib/core/data/history_mode.dart`), with:

- `String get storageName` — `'latest_per_room'` / `'every_video'`.
- `HistoryMode historyModeFromName(String?)` — parses the stored string;
  absent/unknown → **`latestPerRoom`** (the default).

### `collapseHistory`

New pure fn in `lib/core/data/history_collapse.dart`:

```dart
List<HistoryEntry> collapseHistory(List<HistoryEntry> entries, HistoryMode mode);
```

- Input is the newest-first list (as `watchRecent` already orders:
  `playedAt` desc, `id` desc tie-break).
- `everyVideo` → returns the list unchanged (identity).
- `latestPerRoom` → walks the list keeping an entry when **either** its room is
  null/empty **or** that room key has not been seen yet. Because the list is
  newest-first, the first sighting of a room is its latest entry; later
  same-room entries are dropped. Every null/empty-room entry is kept (a solo or
  pre-schema watch is not "in a room").
- Room key = `entry.room` trimmed. Server/port are never part of the key (only
  the bare room code is stored), satisfying the issue's "ignore server/port".
- Preserves input order; does not mutate the input.

### `HistoryStore.watchRecent` gains a mode

```dart
Stream<List<HistoryEntry>> watchRecent({
  int limit = 6,
  HistoryMode mode = HistoryMode.everyVideo,
});
```

- Default stays `everyVideo` so existing callers and tests are unchanged.
- `DriftHistoryStore`:
  - `everyVideo` → current behaviour (order desc, SQL `limit`).
  - `latestPerRoom` → order desc with **no SQL limit**, map through
    `collapseHistory(rows, mode)`, then `.take(limit)`. Collapse happens
    **before** the top-`limit` cut, so a room with many entries can't starve the
    list down to fewer than `limit` distinct rows. History tables are small
    (tens–low hundreds), so fetching unbounded then collapsing is cheap.
- `_pickerInitialDirectory` (HomeScreen, `limit: 1`) keeps the default
  `everyVideo` — the single newest row is identical under either mode, and it
  only wants the most-recent file's folder.

## Part 2 — The toggle (both gears)

- New setting key `kHistoryModeSettingKey = 'history_mode'` in
  `settings_store.dart` (value = `HistoryMode.storageName`; absent/unknown →
  `latestPerRoom`).
- Add a small **"Continue watching"** segmented control to the shared
  `SettingsPanel` (`lib/ui/settings/settings_panel.dart`) — two segments,
  `Latest per room` / `Every video`, styled like the existing `LogLevelControl`
  segmented row. Because both gears render `SettingsPanel`, the toggle appears in
  the lobby gear and in the in-room gear's collapsible Settings section with no
  per-gear duplication.
- `SettingsPanel` gains `HistoryMode historyMode` + `ValueChanged<HistoryMode>
  onHistoryModeChanged`. Both gear wrappers (`LobbySettingsButton`,
  `PlayerMenuButton`) forward these from their owners.

### Connect screen wiring

- `_ConnectScreenState` holds `HistoryMode _historyMode`, loads it in
  `_loadSettings`, and persists changes via the existing `_persistSetting`
  queue (`kHistoryModeSettingKey`).
- `_ContinueWatching` takes the mode and calls
  `history.watchRecent(mode: _historyMode)`. Flipping the toggle calls
  `setState`, which rebuilds the `StreamBuilder` with a new stream → the list
  collapses/expands live.

### Home screen wiring

- `_HomeScreenState` holds `HistoryMode _historyMode`, loads it in
  `_initSettings`, persists on change, and forwards it to `PlayerMenuButton`.
- The in-room list isn't shown inside a room, so flipping it there has no
  immediate visible effect in-room; on returning to the connect screen,
  `_loadSettings` re-reads it and the list reflects the new mode.

## Part 3 — Version/updates in the in-room gear

- A dim, tappable footer row at the very bottom of `_MenuPanel` (below the
  "Leave room" action), visually echoing the connect-screen `VersionBadge`:
  a paw glyph + `v$appVersion` + a short "What's new" affordance.
- Tapping opens the **same `const UpdateDialog()`** the badge opens — check
  version, view changelog, download/apply update. No new update logic.
- Shows the same "update available" dot when the once-per-session silent check
  has already flagged an update. New shared signal
  `lib/core/update/update_availability.dart` exposing a process-wide
  `ValueNotifier<bool> updateAvailable` (default `false`). The badge's existing
  silent check sets `updateAvailable.value = true` alongside its current
  `_hasUpdate` static, so the badge's once-per-session behaviour is unchanged.
  The in-room footer reads it via a `ValueListenableBuilder` and does **not**
  run its own check (the `UpdateDialog` checks on open). The silent check always
  runs on the connect screen, which every session passes through before a room,
  so the flag is settled by the time the in-room gear can show it.
- Menu order after the change (illustrative ASCII, not literal output):

```text
 Room code
 Now playing
 In the room (N)
 ── Load video… / Paste link…
 ── Theme [swatches]
 ▸ Settings
     … (chat-dim) … Notification sounds … Diagnostic logging
     Continue watching: [Latest per room] [Every video]   ← #136 toggle
 ── ← Leave room
 ────────────────
 🐾 v0.32.0-alpha · What's new  ●                          ← NEW footer
```

## Versioning

`feat:` → MINOR bump **0.31.1-alpha → 0.32.0-alpha**, in lockstep across:

- `pubspec.yaml` (`version:`)
- `lib/core/app_version.dart` (`appVersion`)
- `CHANGELOG.md` (new top `## [0.32.0-alpha] - 2026-06-20` entry)

## Testing

- **`collapseHistory`** unit tests: latest-per-room keeps newest per room; null/
  empty-room entries all kept; later same-room entries dropped; `everyVideo`
  identity; order preserved; collapse-before-take-limit fills to `limit` distinct
  rooms when available.
- **`HistoryMode` parse** tests: known names, absent/unknown → `latestPerRoom`,
  round-trip `storageName`.
- **`DriftHistoryStore.watchRecent(mode:)`** test: same DB, `everyVideo` vs
  `latestPerRoom` produce expected row sets; rows are not deleted (flip back
  restores them).
- **Widget tests:** toggle renders + flips in both gears and persists; in-room
  version footer renders `v$appVersion` and opens `UpdateDialog` on tap; update
  dot shows when the session flag is set.
- Existing `watchRecent` callers/tests unaffected (default `everyVideo`).

## Out of scope

- No schema change (the `room`/`username` columns already exist).
- No change to how/when history rows are recorded or how resume works.
- No change to the connect-screen version badge itself.
