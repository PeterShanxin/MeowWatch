# Latest-per-room continue-watching + gear version access — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse "Continue watching" to the latest video per room (with a reversible Settings toggle), and surface version/update access inside the in-room gear.

**Architecture:** Pure, headless-testable logic (`HistoryMode`, `collapseHistory`) drives a new `mode` parameter on `HistoryStore.watchRecent`; collapse is hide-not-delete (filter on read, rows stay in the DB). A shared `SettingsPanel` segmented control puts the toggle in both gears. A process-wide `ValueNotifier` shares the once-per-session "update available" flag so the in-room gear footer mirrors the connect-screen badge.

**Tech Stack:** Flutter (desktop), Drift (SQLite), `flutter_test`. Spec: `docs/superpowers/specs/2026-06-20-latest-per-room-and-gear-version-design.md`.

## Global Constraints

- **Flutter binary (not on PATH):** `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat`. All `analyze`/`test` commands use this absolute path.
- **Work in the worktree:** `d:/Repos/MeowWatch/.claude/worktrees/latest-per-room` on branch `feat/latest-per-room-and-gear-version`. All paths below are relative to that root.
- **Version lockstep (every behavior-changing PR):** bump `pubspec.yaml`, `lib/core/app_version.dart`, `CHANGELOG.md` together. This feature = `feat:` = MINOR bump **0.31.1-alpha → 0.32.0-alpha**. Keep the `-alpha` suffix.
- **Immutability:** never mutate inputs; return new lists/objects (`@immutable` + `copyWith` already used).
- **Theme tokens only:** colours via `context.meow` (`m.accent`, `m.textDim`, `m.surface`, `m.border`, …); spacing/radii/type via `Spacing`/`Radii`/`TypeScale`/`IconSizes`. No hardcoded colours.
- **Commit messages:** conventional (`feat:`/`test:`/`chore:`). No Claude attribution / self-stamp in any commit text.
- **Default history mode = `latestPerRoom`** everywhere a *setting* default is needed; the `watchRecent` method param default stays `everyVideo` so existing callers/tests are untouched.

---

### Task 1: `HistoryMode` enum + parser

**Files:**
- Create: `lib/core/data/history_mode.dart`
- Test: `test/core/data/history_mode_test.dart`

**Interfaces:**
- Produces: `enum HistoryMode { latestPerRoom, everyVideo }`; `String HistoryMode.storageName`; top-level `HistoryMode historyModeFromName(String? name)` (absent/unknown → `latestPerRoom`).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/data/history_mode_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/history_mode.dart';

void main() {
  test('storageName round-trips through historyModeFromName', () {
    for (final mode in HistoryMode.values) {
      expect(historyModeFromName(mode.storageName), mode);
    }
  });

  test('storageName values are stable snake_case', () {
    expect(HistoryMode.latestPerRoom.storageName, 'latest_per_room');
    expect(HistoryMode.everyVideo.storageName, 'every_video');
  });

  test('absent or unknown name falls back to latestPerRoom', () {
    expect(historyModeFromName(null), HistoryMode.latestPerRoom);
    expect(historyModeFromName(''), HistoryMode.latestPerRoom);
    expect(historyModeFromName('garbage'), HistoryMode.latestPerRoom);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/data/history_mode_test.dart`
Expected: FAIL — `history_mode.dart` does not exist / `HistoryMode` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/data/history_mode.dart

/// How the "Continue watching" list treats multiple videos watched in the same
/// room. [latestPerRoom] keeps only the most-recently-played file per room
/// (older same-room entries are hidden, not deleted); [everyVideo] shows them
/// all. Persisted under `kHistoryModeSettingKey` via [storageName].
enum HistoryMode {
  latestPerRoom,
  everyVideo;

  String get storageName => switch (this) {
        HistoryMode.latestPerRoom => 'latest_per_room',
        HistoryMode.everyVideo => 'every_video',
      };
}

/// Parse a persisted [HistoryMode.storageName]. Absent or unrecognized values
/// fall back to [HistoryMode.latestPerRoom] — the product default.
HistoryMode historyModeFromName(String? name) {
  for (final mode in HistoryMode.values) {
    if (mode.storageName == name) return mode;
  }
  return HistoryMode.latestPerRoom;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/data/history_mode_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/data/history_mode.dart test/core/data/history_mode_test.dart
git commit -m "feat: add HistoryMode enum + parser for continue-watching modes"
```

---

### Task 2: `collapseHistory` pure function

**Files:**
- Create: `lib/core/data/history_collapse.dart`
- Test: `test/core/data/history_collapse_test.dart`

**Interfaces:**
- Consumes: `HistoryMode` (Task 1), `HistoryEntry` (`lib/core/data/history_entry.dart`).
- Produces: `List<HistoryEntry> collapseHistory(List<HistoryEntry> entries, HistoryMode mode)` — input is newest-first; returns a new list, input unchanged.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/data/history_collapse_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/history_collapse.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/history_mode.dart';

HistoryEntry _e(int id, {String? room}) => HistoryEntry(
      id: id,
      filePath: 'p$id',
      fileName: 'f$id',
      fileSizeBytes: 1,
      durationMs: null,
      lastPositionMs: 0,
      // playedAt only matters for ordering, which the input already encodes.
      playedAt: DateTime.fromMillisecondsSinceEpoch(id),
      room: room,
    );

void main() {
  // Newest-first input, as watchRecent emits.
  final newestFirst = <HistoryEntry>[
    _e(5, room: 'cozy'), // latest in cozy
    _e(4, room: 'cozy'),
    _e(3, room: 'breezy'), // latest in breezy
    _e(2), // solo (no room)
    _e(1, room: 'cozy'),
  ];

  test('everyVideo is identity (same order, same items)', () {
    final out = collapseHistory(newestFirst, HistoryMode.everyVideo);
    expect(out.map((e) => e.id).toList(), [5, 4, 3, 2, 1]);
  });

  test('latestPerRoom keeps newest per room and all room-less entries', () {
    final out = collapseHistory(newestFirst, HistoryMode.latestPerRoom);
    // cozy collapses to id 5; breezy stays at 3; solo id 2 always kept.
    expect(out.map((e) => e.id).toList(), [5, 3, 2]);
  });

  test('latestPerRoom keeps every room-less entry (empty string == no room)', () {
    final input = <HistoryEntry>[_e(3, room: ''), _e(2), _e(1, room: 'r')];
    final out = collapseHistory(input, HistoryMode.latestPerRoom);
    expect(out.map((e) => e.id).toList(), [3, 2, 1]);
  });

  test('does not mutate the input list', () {
    final input = <HistoryEntry>[_e(2, room: 'r'), _e(1, room: 'r')];
    collapseHistory(input, HistoryMode.latestPerRoom);
    expect(input.map((e) => e.id).toList(), [2, 1]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/data/history_collapse_test.dart`
Expected: FAIL — `history_collapse.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/data/history_collapse.dart
import 'history_entry.dart';
import 'history_mode.dart';

/// Apply the continue-watching [mode] to a newest-first [entries] list.
///
/// [HistoryMode.everyVideo] returns the list unchanged. [HistoryMode.latestPerRoom]
/// keeps an entry when its room is null/empty (a solo or pre-schema watch is not
/// "in a room") OR when that room's bare code has not been seen yet — because the
/// list is newest-first, the first sighting of a room is its latest entry, so
/// later same-room entries are dropped. Hide-not-delete: this filters the view
/// only; nothing is removed from storage. The input is never mutated.
List<HistoryEntry> collapseHistory(List<HistoryEntry> entries, HistoryMode mode) {
  if (mode == HistoryMode.everyVideo) {
    return List<HistoryEntry>.of(entries);
  }
  final seenRooms = <String>{};
  final out = <HistoryEntry>[];
  for (final entry in entries) {
    final room = entry.room?.trim() ?? '';
    if (room.isEmpty) {
      out.add(entry);
      continue;
    }
    if (seenRooms.add(room)) out.add(entry);
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/data/history_collapse_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/data/history_collapse.dart test/core/data/history_collapse_test.dart
git commit -m "feat: add collapseHistory (latest-per-room view filter)"
```

---

### Task 3: `watchRecent(mode:)` — interface, Drift impl, fakes

**Files:**
- Modify: `lib/core/data/stores.dart` (the `HistoryStore.watchRecent` signature + doc)
- Modify: `lib/core/data/drift_stores.dart:84-94` (`DriftHistoryStore.watchRecent`)
- Modify: `test/support/fakes.dart:39` (`FakeHistoryStore.watchRecent`)
- Modify: `test/ui/connect/connect_screen_test.dart:86` (`_FakeHistoryStore.watchRecent`)
- Test: `test/core/data/drift_history_store_test.dart` (add cases)

**Interfaces:**
- Consumes: `HistoryMode` (Task 1), `collapseHistory` (Task 2).
- Produces: `Stream<List<HistoryEntry>> watchRecent({int limit = 6, HistoryMode mode = HistoryMode.everyVideo})` — for `latestPerRoom`, collapses the full ordered set, then takes `limit`.

- [ ] **Step 1: Write the failing test (add to the existing file)**

```dart
// Append inside main() in test/core/data/drift_history_store_test.dart.
// Add this import at the top of the file:
//   import 'package:meowwatch/core/data/history_mode.dart';

  test('latestPerRoom hides older same-room entries but keeps the rows',
      () async {
    await store.recordOpen(
        filePath: 'a', fileName: 'a', fileSizeBytes: 1, room: 'cozy');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(
        filePath: 'b', fileName: 'b', fileSizeBytes: 1, room: 'cozy');

    final collapsed =
        await store.watchRecent(mode: HistoryMode.latestPerRoom).first;
    expect(collapsed.map((e) => e.fileName).toList(), ['b']);

    // Hide-not-delete: everyVideo still sees both rows (nothing was removed).
    final all = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(all.map((e) => e.fileName).toList(), ['b', 'a']);
  });

  test('latestPerRoom keeps room-less entries and fills limit after collapse',
      () async {
    // cozy x2 (collapses to 1) + two solo files → limit:2 should yield 2 rows.
    await store.recordOpen(
        filePath: 'a', fileName: 'a', fileSizeBytes: 1, room: 'cozy');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(filePath: 'b', fileName: 'b', fileSizeBytes: 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(
        filePath: 'c', fileName: 'c', fileSizeBytes: 1, room: 'cozy');

    final list =
        await store.watchRecent(limit: 2, mode: HistoryMode.latestPerRoom).first;
    // newest-first c(cozy), b(solo), a(cozy→hidden) → collapse → [c, b] → take 2.
    expect(list.map((e) => e.fileName).toList(), ['c', 'b']);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/data/drift_history_store_test.dart`
Expected: FAIL — `watchRecent` has no `mode` parameter.

- [ ] **Step 3: Implement — interface**

In `lib/core/data/stores.dart`, add the import and update the signature + doc:

```dart
// top of file, with the other imports:
import 'history_mode.dart';
```

```dart
  /// Live list, most-recently-played first. [mode] selects how same-room
  /// videos are shown: [HistoryMode.latestPerRoom] hides older same-room
  /// entries (view filter only — rows stay in storage), [HistoryMode.everyVideo]
  /// shows them all. The collapse runs before [limit] is applied.
  Stream<List<HistoryEntry>> watchRecent({
    int limit = 6,
    HistoryMode mode = HistoryMode.everyVideo,
  });
```

- [ ] **Step 4: Implement — Drift store**

In `lib/core/data/drift_stores.dart`, add imports and replace `watchRecent`:

```dart
// with the other imports at the top of the file:
import 'history_collapse.dart';
import 'history_mode.dart';
```

```dart
  @override
  Stream<List<HistoryEntry>> watchRecent({
    int limit = 6,
    HistoryMode mode = HistoryMode.everyVideo,
  }) {
    // playedAt ties at whole-second resolution; id desc is the stable
    // tie-break so the newest write wins.
    final query = _db.select(_db.historyEntries)
      ..orderBy([
        (t) => OrderingTerm(expression: t.playedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    if (mode == HistoryMode.everyVideo) {
      query.limit(limit);
      return query.watch().map((rows) => rows.map(_toModel).toList());
    }
    // latestPerRoom: collapse the full ordered set first, THEN take `limit` —
    // a limit-then-collapse could under-fill when one room has many entries.
    return query.watch().map(
          (rows) => collapseHistory(rows.map(_toModel).toList(), mode)
              .take(limit)
              .toList(),
        );
  }
```

- [ ] **Step 5: Implement — update both fakes**

In `test/support/fakes.dart`, add the import and update the override:

```dart
// with the other imports:
import 'package:meowwatch/core/data/history_mode.dart';
```

```dart
  @override
  Stream<List<HistoryEntry>> watchRecent({
    int limit = 6,
    HistoryMode mode = HistoryMode.everyVideo,
  }) async* {
    // (keep the existing body unchanged)
```

In `test/ui/connect/connect_screen_test.dart`, add the import (if absent) and update `_FakeHistoryStore.watchRecent` the same way:

```dart
// with the other imports:
import 'package:meowwatch/core/data/history_mode.dart';
```

```dart
  @override
  Stream<List<HistoryEntry>> watchRecent({
    int limit = 6,
    HistoryMode mode = HistoryMode.everyVideo,
  }) async* {
    // (keep the existing body unchanged)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/data/drift_history_store_test.dart test/support/fakes.dart`
Expected: PASS (existing cases + 2 new). Then a quick analyze:
Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat analyze lib/core/data`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/core/data/stores.dart lib/core/data/drift_stores.dart test/support/fakes.dart test/ui/connect/connect_screen_test.dart test/core/data/drift_history_store_test.dart
git commit -m "feat: add HistoryMode to watchRecent (latest-per-room collapse)"
```

---

### Task 4: `kHistoryModeSettingKey` + SettingsPanel toggle

**Files:**
- Modify: `lib/core/data/settings_store.dart` (new key constant)
- Modify: `lib/ui/settings/settings_panel.dart` (`SettingsPanel` gains 2 params + new `HistoryModeControl`)
- Test: `test/ui/settings/settings_panel_test.dart` (update `_panel` helper + add cases)

**Interfaces:**
- Consumes: `HistoryMode` (Task 1).
- Produces: `const String kHistoryModeSettingKey = 'history_mode'`; `SettingsPanel` requires `HistoryMode historyMode` + `ValueChanged<HistoryMode> onHistoryModeChanged`; widget `HistoryModeControl({required HistoryMode value, required ValueChanged<HistoryMode> onChanged})`; segment keys `Key('history-mode-<storageName>')`.

- [ ] **Step 1: Write the failing test (update helper + add cases)**

In `test/ui/settings/settings_panel_test.dart`, add imports:

```dart
import 'package:meowwatch/core/data/history_mode.dart';
import 'package:meowwatch/core/data/settings_store.dart';
```

Add the two params to the `_panel` helper (defaults shown), passing them into `SettingsPanel`:

```dart
  HistoryMode historyMode = HistoryMode.latestPerRoom,
  ValueChanged<HistoryMode>? onHistoryModeChanged,
```
```dart
  historyMode: historyMode,
  onHistoryModeChanged: onHistoryModeChanged ?? (_) {},
```

Add cases:

```dart
  testWidgets('renders the Continue watching toggle', (tester) async {
    await tester.pumpWidget(_host(_panel()));
    expect(find.text('Continue watching'), findsOneWidget);
    expect(
      find.byKey(Key('history-mode-${HistoryMode.latestPerRoom.storageName}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('history-mode-${HistoryMode.everyVideo.storageName}')),
      findsOneWidget,
    );
  });

  testWidgets('picking Every video fires onHistoryModeChanged', (tester) async {
    HistoryMode? picked;
    await tester.pumpWidget(
      _host(_panel(onHistoryModeChanged: (v) => picked = v)),
    );
    await tester
        .tap(find.byKey(Key('history-mode-${HistoryMode.everyVideo.storageName}')));
    expect(picked, HistoryMode.everyVideo);
  });

  test('kHistoryModeSettingKey is stable', () {
    expect(kHistoryModeSettingKey, 'history_mode');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/settings/settings_panel_test.dart`
Expected: FAIL — `SettingsPanel` has no `historyMode`; `kHistoryModeSettingKey` undefined.

- [ ] **Step 3: Implement — setting key**

In `lib/core/data/settings_store.dart`, add above the `SettingsStore` interface:

```dart
/// Key for the persisted continue-watching mode (value = a HistoryMode
/// `storageName`: `latest_per_room` / `every_video`; absent/unknown →
/// `latestPerRoom`).
const String kHistoryModeSettingKey = 'history_mode';
```

- [ ] **Step 4: Implement — SettingsPanel + HistoryModeControl**

In `lib/ui/settings/settings_panel.dart`, add the import:

```dart
import '../../core/data/history_mode.dart';
```

Add the two fields + constructor params to `SettingsPanel`:

```dart
  final HistoryMode historyMode;
  final ValueChanged<HistoryMode> onHistoryModeChanged;
```
```dart
    required this.historyMode,
    required this.onHistoryModeChanged,
```

Add the control at the **top** of the panel's `children` (before the sound pickers), with a divider after it:

```dart
        HistoryModeControl(
          value: historyMode,
          onChanged: onHistoryModeChanged,
        ),
        Divider(color: m.border, height: Spacing.lg),
        SoundPickerRow(
          // ...existing primary picker unchanged...
```

Add the new control widget (mirrors `LogLevelControl`, reuses the existing private `_LogLevelSegment`):

```dart
/// Two-way continue-watching mode picker (Latest per room / Every video) shown
/// as a labelled segmented row, matching [LogLevelControl]. Picking a segment
/// fires [onChanged]. Public so it can be unit-tested directly.
class HistoryModeControl extends StatelessWidget {
  const HistoryModeControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final HistoryMode value;
  final ValueChanged<HistoryMode> onChanged;

  static const Map<HistoryMode, String> _labels = <HistoryMode, String>{
    HistoryMode.latestPerRoom: 'Latest per room',
    HistoryMode.everyVideo: 'Every video',
  };

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Continue watching',
            style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              for (final mode in HistoryMode.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: mode == HistoryMode.everyVideo ? 0 : Spacing.xs,
                    ),
                    child: _LogLevelSegment(
                      key: Key('history-mode-${mode.storageName}'),
                      text: _labels[mode]!,
                      selected: mode == value,
                      onTap: () => onChanged(mode),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/settings/settings_panel_test.dart`
Expected: PASS (existing + 3 new). This intentionally breaks the two gear call-sites (compile errors) — fixed in Tasks 5 and 6.

- [ ] **Step 6: Commit**

```bash
git add lib/core/data/settings_store.dart lib/ui/settings/settings_panel.dart test/ui/settings/settings_panel_test.dart
git commit -m "feat: add Continue-watching mode toggle to shared SettingsPanel"
```

---

### Task 5: Wire the toggle through the lobby gear + connect screen

**Files:**
- Modify: `lib/ui/settings/lobby_settings_button.dart` (forward 2 params)
- Modify: `lib/ui/connect/connect_screen.dart` (state, load/persist, pass to `_ContinueWatching` + `LobbySettingsButton`)
- Test: `test/ui/settings/lobby_settings_button_test.dart` (update builder)
- Test: `test/ui/connect/connect_screen_test.dart` (collapse behavior — the fake already updated in Task 3)

**Interfaces:**
- Consumes: `HistoryMode` (Task 1), `kHistoryModeSettingKey` (Task 4), `SettingsPanel` params (Task 4), `watchRecent(mode:)` (Task 3).
- Produces: `LobbySettingsButton` requires `HistoryMode historyMode` + `ValueChanged<HistoryMode> onHistoryModeChanged`; `_ContinueWatching` takes `HistoryMode mode`.

- [ ] **Step 1: Write the failing test**

In `test/ui/settings/lobby_settings_button_test.dart`, update its `_button`/builder helper to pass the new required params (mirror how `settings_panel_test` did it):

```dart
// add import:
import 'package:meowwatch/core/data/history_mode.dart';
// in the builder's params:
  HistoryMode historyMode = HistoryMode.latestPerRoom,
  ValueChanged<HistoryMode>? onHistoryModeChanged,
// in the LobbySettingsButton(...) construction:
  historyMode: historyMode,
  onHistoryModeChanged: onHistoryModeChanged ?? (_) {},
```

In `test/ui/connect/connect_screen_test.dart`, give the `_FakeHistoryStore` seed data with two same-room files, then assert the list collapses by default. Find the existing `_FakeHistoryStore` and ensure its `watchRecent` honours `mode` by delegating to `collapseHistory` (so the fake mirrors production):

```dart
// add imports:
import 'package:meowwatch/core/data/history_collapse.dart';
import 'package:meowwatch/core/data/history_mode.dart';
// inside _FakeHistoryStore.watchRecent body, replace the emit with:
    yield collapseHistory(_entries, mode).take(limit).toList();
// (where _entries is the fake's newest-first backing list)
```

Add a widget test (mirror the file's existing ConnectScreen pump harness — reuse its existing `_pumpConnect`/setup helper):

```dart
  testWidgets('Continue watching collapses to latest per room by default',
      (tester) async {
    // Two files in the same room; newest is ep2.
    history.seed(<HistoryEntry>[
      _historyEntry(id: 2, fileName: 'ep2.mkv', room: 'cozy'),
      _historyEntry(id: 1, fileName: 'ep1.mkv', room: 'cozy'),
    ]);
    await _pumpConnect(tester);
    await tester.pumpAndSettle();
    expect(find.text('ep2.mkv'), findsOneWidget);
    expect(find.text('ep1.mkv'), findsNothing);
  });
```

> Note for the implementer: match the exact fake API already in this test file
> (its constructor, any `seed`/backing-field name, and the `_historyEntry`/pump
> helpers). If the fake has no seeding hook, add a minimal `seed(List<HistoryEntry>)`
> that stores a newest-first list the `watchRecent` override reads. Do not change
> unrelated existing tests.

- [ ] **Step 2: Run test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/settings/lobby_settings_button_test.dart test/ui/connect/connect_screen_test.dart`
Expected: FAIL — `LobbySettingsButton`/`ConnectScreen` don't compile yet (missing params / `_ContinueWatching` has no `mode`).

- [ ] **Step 3: Implement — LobbySettingsButton**

In `lib/ui/settings/lobby_settings_button.dart`, add the import, two fields + constructor params, and forward them into `SettingsPanel`:

```dart
import '../../core/data/history_mode.dart';
```
```dart
  final HistoryMode historyMode;
  final ValueChanged<HistoryMode> onHistoryModeChanged;
```
```dart
    required this.historyMode,
    required this.onHistoryModeChanged,
```
In the `SettingsPanel(...)` call inside `_panel`:
```dart
              SettingsPanel(
                historyMode: widget.historyMode,
                onHistoryModeChanged: widget.onHistoryModeChanged,
                primarySoundId: widget.primarySoundId,
                // ...rest unchanged...
```

- [ ] **Step 4: Implement — connect screen**

In `lib/ui/connect/connect_screen.dart`:

Add the import:
```dart
import '../../core/data/history_mode.dart';
```
Add state field (near `_logLevel`):
```dart
  HistoryMode _historyMode = HistoryMode.latestPerRoom;
```
In `_loadSettings`, read it and set it (inside the existing `setState`):
```dart
    final historyMode = historyModeFromName(
      await widget.settings.get(kHistoryModeSettingKey),
    );
```
```dart
      _historyMode = historyMode;
```
Add a setter near `_setLogLevel`:
```dart
  void _setHistoryMode(HistoryMode mode) {
    appLog('settings: history mode=${mode.storageName}');
    setState(() => _historyMode = mode);
    _persistSetting(kHistoryModeSettingKey, mode.storageName);
  }
```
Pass to `LobbySettingsButton` (in `build`):
```dart
            child: LobbySettingsButton(
              historyMode: _historyMode,
              onHistoryModeChanged: _setHistoryMode,
              currentTheme: widget.currentTheme,
              // ...rest unchanged...
```
Pass the mode into `_ContinueWatching` (in `_libraryColumn`):
```dart
      _ContinueWatching(
        history: widget.history,
        mode: _historyMode,
        currentUsername: _typedUsername,
        onResume: (entry, {usernameOverride}) => _resumeHistory(
```
Add the field + use it in `_ContinueWatching`:
```dart
class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({
    required this.history,
    required this.mode,
    required this.currentUsername,
    required this.onResume,
  });

  final HistoryStore history;
  final HistoryMode mode;
  final String currentUsername;
  final void Function(HistoryEntry entry, {String? usernameOverride}) onResume;
```
```dart
      stream: history.watchRecent(mode: mode),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/settings/lobby_settings_button_test.dart test/ui/connect/connect_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/settings/lobby_settings_button.dart lib/ui/connect/connect_screen.dart test/ui/settings/lobby_settings_button_test.dart test/ui/connect/connect_screen_test.dart
git commit -m "feat: wire Continue-watching toggle through lobby gear + connect screen"
```

---

### Task 6: Wire the toggle through the in-room gear + home screen

**Files:**
- Modify: `lib/ui/player_menu_button.dart` (`PlayerMenuButton` + `_MenuPanel` forward 2 params)
- Modify: `lib/ui/home_screen.dart` (state, load/persist, pass to `PlayerMenuButton`)
- Test: `test/ui/player_menu_button_test.dart` (update `_button` helper + add a case)

**Interfaces:**
- Consumes: `HistoryMode` (Task 1), `kHistoryModeSettingKey` (Task 4), `SettingsPanel` params (Task 4).
- Produces: `PlayerMenuButton` requires `HistoryMode historyMode` + `ValueChanged<HistoryMode> onHistoryModeChanged`.

- [ ] **Step 1: Write the failing test**

In `test/ui/player_menu_button_test.dart`, add the import and the two params to the `_button` helper (defaults), passing them into `PlayerMenuButton`:

```dart
import 'package:meowwatch/core/data/history_mode.dart';
```
```dart
  HistoryMode historyMode = HistoryMode.latestPerRoom,
  ValueChanged<HistoryMode>? onHistoryModeChanged,
```
```dart
  historyMode: historyMode,
  onHistoryModeChanged: onHistoryModeChanged ?? (_) {},
```

Add a case (uses the existing `_openSettings` helper that opens the gear + expands Settings):

```dart
  testWidgets('Continue-watching toggle fires onHistoryModeChanged', (
    tester,
  ) async {
    HistoryMode? picked;
    await tester.pumpWidget(
      _host(_button(onHistoryModeChanged: (v) => picked = v)),
    );
    await _openSettings(tester);
    await _tap(
      tester,
      find.byKey(Key('history-mode-${HistoryMode.everyVideo.storageName}')),
    );
    expect(picked, HistoryMode.everyVideo);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/player_menu_button_test.dart`
Expected: FAIL — `PlayerMenuButton` has no `historyMode`.

- [ ] **Step 3: Implement — PlayerMenuButton + _MenuPanel**

In `lib/ui/player_menu_button.dart`, add the import:
```dart
import '../core/data/history_mode.dart';
```
Add fields + constructor params to **both** `PlayerMenuButton` and `_MenuPanel`:
```dart
  final HistoryMode historyMode;
  final ValueChanged<HistoryMode> onHistoryModeChanged;
```
```dart
    required this.historyMode,
    required this.onHistoryModeChanged,
```
In `PlayerMenuButton.build`, forward into the `_MenuPanel(...)`:
```dart
          child: _MenuPanel(
            historyMode: historyMode,
            onHistoryModeChanged: onHistoryModeChanged,
            roomCode: roomCode,
            // ...rest unchanged...
```
In `_MenuPanelState.build`, forward into the `SettingsPanel(...)` (inside the expanded Settings column):
```dart
                          SettingsPanel(
                            historyMode: widget.historyMode,
                            onHistoryModeChanged: widget.onHistoryModeChanged,
                            primarySoundId: widget.primarySoundId,
                            // ...rest unchanged...
```

- [ ] **Step 4: Implement — home screen**

In `lib/ui/home_screen.dart`:

Add the import:
```dart
import '../core/data/history_mode.dart';
```
Add state field (near `_logLevel`):
```dart
  HistoryMode _historyMode = HistoryMode.latestPerRoom;
```
In `_initSettings`, read + set it:
```dart
    final historyMode = historyModeFromName(
      await widget.settings.get(kHistoryModeSettingKey),
    );
    if (mounted) setState(() => _historyMode = historyMode);
```
Pass to `PlayerMenuButton` (in `build`), with an inline setter that persists:
```dart
                          child: PlayerMenuButton(
                            historyMode: _historyMode,
                            onHistoryModeChanged: (mode) {
                              appLog('settings: history mode=${mode.storageName}');
                              setState(() => _historyMode = mode);
                              widget.settings.set(
                                kHistoryModeSettingKey,
                                mode.storageName,
                              );
                            },
                            roomCode: encodeShareCode(
                            // ...rest unchanged...
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/player_menu_button_test.dart`
Expected: PASS (existing + new). Then analyze the touched UI:
Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat analyze lib/ui`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/ui/player_menu_button.dart lib/ui/home_screen.dart test/ui/player_menu_button_test.dart
git commit -m "feat: wire Continue-watching toggle through in-room gear + home screen"
```

---

### Task 7: Shared `updateAvailable` notifier + badge sets it

**Files:**
- Create: `lib/core/update/update_availability.dart`
- Modify: `lib/ui/version_badge.dart` (set the notifier in `_silentCheck`; reset in `resetForTest`)
- Test: `test/ui/version_badge_test.dart` (assert the notifier flips)

**Interfaces:**
- Produces: `final ValueNotifier<bool> updateAvailable` (process-wide, default `false`).

- [ ] **Step 1: Write the failing test (add to the existing file)**

```dart
// add import at top of test/ui/version_badge_test.dart:
import 'package:meowwatch/core/update/update_availability.dart';

// add inside main():
  testWidgets('silent check sets the shared updateAvailable notifier',
      (tester) async {
    expect(updateAvailable.value, isFalse);
    await tester.pumpWidget(host(factoryFor(clientReporting('99.0.0'))));
    await tester.pumpAndSettle();
    expect(updateAvailable.value, isTrue);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/version_badge_test.dart --plain-name "shared updateAvailable"`
Expected: FAIL — `update_availability.dart` does not exist.

- [ ] **Step 3: Implement — notifier**

```dart
// lib/core/update/update_availability.dart
import 'package:flutter/foundation.dart';

/// Process-wide "an update was found this session" flag. Set by the connect
/// screen's once-per-session silent check ([VersionBadge]) and read by any
/// surface that wants to show an update dot without running its own check —
/// e.g. the in-room gear's version footer. Mirrors the badge's dot so both
/// surfaces agree. Reset in tests via VersionBadge.resetForTest().
final ValueNotifier<bool> updateAvailable = ValueNotifier<bool>(false);
```

- [ ] **Step 4: Implement — badge sets + resets it**

In `lib/ui/version_badge.dart`, add the import:
```dart
import '../core/update/update_availability.dart';
```
In `_silentCheck`, where `_hasUpdate = true;` is set, also set the shared flag:
```dart
        _hasUpdate = true;
        updateAvailable.value = true;
```
In `VersionBadge.resetForTest`, clear it too (keeps tests order-independent):
```dart
    _VersionBadgeState._hasUpdate = false;
    updateAvailable.value = false;
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/version_badge_test.dart`
Expected: PASS (existing + new).

- [ ] **Step 6: Commit**

```bash
git add lib/core/update/update_availability.dart lib/ui/version_badge.dart test/ui/version_badge_test.dart
git commit -m "feat: share once-per-session update-available flag via a notifier"
```

---

### Task 8: In-room gear version footer

**Files:**
- Modify: `lib/ui/player_menu_button.dart` (add `_VersionFooter` at the bottom of `_MenuPanel`)
- Test: `test/ui/player_menu_button_test.dart` (footer renders, opens dialog, shows dot)

**Interfaces:**
- Consumes: `appVersion` (`lib/core/app_version.dart`), `UpdateDialog` (`lib/ui/update_dialog.dart`), `updateAvailable` (Task 7).
- Produces: footer `InkWell` key `Key('player-menu-version')`; update dot key `Key('player-menu-update-dot')`.

- [ ] **Step 1: Write the failing test (add to the existing file)**

```dart
// add imports at top of test/ui/player_menu_button_test.dart:
import 'package:meowwatch/core/app_version.dart';
import 'package:meowwatch/core/update/update_availability.dart';

// add inside main():
  // The footer dot reads a process-wide notifier — keep tests independent.
  setUp(() => updateAvailable.value = false);
  tearDown(() => updateAvailable.value = false);

  testWidgets('in-room gear shows a tappable version footer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(_button()));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    final footer = find.byKey(const Key('player-menu-version'));
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();
    expect(find.text('v$appVersion'), findsOneWidget);
  });

  testWidgets('tapping the version footer opens the UpdateDialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(_button()));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('player-menu-version')));
    expect(find.text('MeowWatch Updates'), findsOneWidget);
  });

  testWidgets('version footer shows the update dot when one is available',
      (tester) async {
    updateAvailable.value = true;
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(_button()));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    final dot = find.byKey(const Key('player-menu-update-dot'));
    await tester.ensureVisible(dot);
    expect(dot, findsOneWidget);
  });
```

> Note: the "opens the UpdateDialog" case mirrors the existing `version_badge_test`
> case of the same shape — `const UpdateDialog()` over `UpdateService.instance` is
> the established, test-safe pattern there (the dialog renders its title before the
> async check resolves), so `pumpAndSettle` + `find.text('MeowWatch Updates')` works.

- [ ] **Step 2: Run test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/player_menu_button_test.dart --plain-name "version footer"`
Expected: FAIL — no `player-menu-version` key.

- [ ] **Step 3: Implement — footer widget + mount it**

In `lib/ui/player_menu_button.dart`, add imports:
```dart
import '../core/app_version.dart';
import '../core/update/update_availability.dart';
import 'update_dialog.dart';
```
At the very end of `_MenuPanelState.build`'s `children` (after the existing `_MenuAction(key: Key('player-menu-leave'), ...)`), add a divider + footer:
```dart
              Divider(color: m.border, height: Spacing.lg),
              const _VersionFooter(),
```
Add the widget (echoes the connect-screen `VersionBadge` chip styling; dim, tappable, opens the same dialog; reads the shared notifier for the dot):
```dart
/// Dim, tappable version line at the bottom of the in-room gear — the in-room
/// counterpart to the connect screen's [VersionBadge] (there is no badge inside
/// a room). Opens the same [UpdateDialog] (check version, changelog, update) and
/// shows the shared "update available" dot when this session's silent check has
/// found one.
class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  void _open(BuildContext context) {
    // Capture the root navigator's context BEFORE closing the menu, so the
    // dialog has a live context even though this footer's own context is torn
    // down as the menu closes.
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    MenuController.maybeOf(context)?.close();
    showDialog<void>(
      context: rootContext,
      builder: (_) => const UpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Tooltip(
      message: "Updates & what's new",
      child: InkWell(
        key: const Key('player-menu-version'),
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pets, size: 12, color: m.textDim),
              const SizedBox(width: Spacing.xs),
              Text(
                'v$appVersion',
                style: TextStyle(
                  color: m.textDim,
                  fontSize: TypeScale.caption,
                  fontWeight: TypeScale.medium,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                "· What's new",
                style: TextStyle(
                  color: m.textDim,
                  fontSize: TypeScale.caption,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: updateAvailable,
                builder: (context, hasUpdate, _) {
                  if (!hasUpdate) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: Spacing.sm),
                    child: Container(
                      key: const Key('player-menu-update-dot'),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/player_menu_button_test.dart`
Expected: PASS (all cases). Then analyze:
Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat analyze lib/ui/player_menu_button.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player_menu_button.dart test/ui/player_menu_button_test.dart
git commit -m "feat: add version/updates footer to the in-room gear"
```

---

### Task 9: Version bump + full gate

**Files:**
- Modify: `pubspec.yaml` (`version:`)
- Modify: `lib/core/app_version.dart` (`appVersion`)
- Modify: `CHANGELOG.md` (new top entry)

**Interfaces:** none (release metadata).

- [ ] **Step 1: Bump `pubspec.yaml`**

Change the `version:` line from `0.31.1-alpha+...`/`0.31.1-alpha` to `0.32.0-alpha` (preserve any `+build` convention already used in the file — match the existing format exactly; if the current line is `version: 0.31.1-alpha`, set `version: 0.32.0-alpha`).

- [ ] **Step 2: Bump `lib/core/app_version.dart`**

Change `const String appVersion = '0.31.1-alpha';` → `const String appVersion = '0.32.0-alpha';`.

- [ ] **Step 3: Add the `CHANGELOG.md` entry**

Insert a new entry directly above the current top `## [0.31.1-alpha]` entry:

```markdown
## [0.32.0-alpha] - 2026-06-20

### Added
- Continue watching now keeps only the latest video per room by default, with a
  Settings toggle ("Latest per room" / "Every video") in both the lobby and the
  in-room gear. Older same-room entries are hidden, not deleted — flip the toggle
  to bring them all back. (#136)
- The in-room gear now has a version/updates footer (check version, see what's
  new, update) — the same as the connect-screen version badge.
```

- [ ] **Step 4: Verify the three are in lockstep**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat analyze`
Expected: `No issues found!`
Then confirm the version string matches in all three:
Run: `git grep -n "0.32.0-alpha" pubspec.yaml lib/core/app_version.dart CHANGELOG.md`
Expected: a hit in each of the three files.

- [ ] **Step 5: Full test suite**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test`
Expected: all tests pass. (If a golden test fails, no chat/golden widget was touched by this plan — investigate rather than blindly updating goldens.)

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml lib/core/app_version.dart CHANGELOG.md
git commit -m "chore: bump version to 0.32.0-alpha"
```

---

## Self-Review

**Spec coverage:**
- Part 1 (data layer): `HistoryMode` (Task 1), `collapseHistory` hide-not-delete (Task 2), `watchRecent(mode:)` collapse-before-limit + `_pickerInitialDirectory` unaffected default (Task 3). ✓
- Part 2 (toggle in both gears): `kHistoryModeSettingKey` + `SettingsPanel` control (Task 4), lobby+connect wiring with live re-subscribe (Task 5), in-room+home wiring (Task 6). ✓
- Part 3 (in-room version): shared `updateAvailable` notifier (Task 7), footer opening `UpdateDialog` + dot (Task 8). ✓
- Versioning 0.31.1→0.32.0-alpha lockstep (Task 9). ✓
- Lobby gear gets no version row — confirmed: Task 5 only adds the toggle to the lobby gear; the footer (Task 8) is added solely to `player_menu_button.dart`. ✓

**Placeholder scan:** No TBD/TODO/"add error handling" placeholders; every code step shows full code. The two notes (connect-screen fake API in Task 5, UpdateDialog test-safety in Task 8) are guidance about matching existing patterns, not deferred work.

**Type consistency:** `HistoryMode`, `historyModeFromName`, `collapseHistory(List<HistoryEntry>, HistoryMode)`, `watchRecent({int limit, HistoryMode mode})`, `kHistoryModeSettingKey`, `SettingsPanel.historyMode/onHistoryModeChanged`, `HistoryModeControl(value/onChanged)`, segment key `history-mode-<storageName>`, footer key `player-menu-version`, dot key `player-menu-update-dot`, `updateAvailable` — names are used identically across tasks.

**Note on default param vs. setting default:** `watchRecent`'s `mode` defaults to `everyVideo` (back-compat for the picker + untouched tests); the *setting* and every UI/state default is `latestPerRoom`. This split is intentional and consistent across Tasks 3, 5, 6.
