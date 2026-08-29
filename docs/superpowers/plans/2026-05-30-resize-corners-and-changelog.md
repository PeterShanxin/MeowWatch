# Four-Corner Resize + Multi-Version Changelog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resize the chat card from any of its four corners (with a real, draggable height), add hover tooltips to the card's buttons, and show a scrollable multi-version changelog in the updater sourced from `CHANGELOG.md` via R2.

**Architecture:** Resize geometry stays a pure function (`computeCornerResize`) returning a new top-left + size with the opposite corner pinned; the widget free-floats during the drag (reusing `_dragTopLeft`/`_dragCardSize`) and glides back to its docked corner. The card switches from a content-hugging max-height to a fixed height so height is resizable. The updater gains a `fetchChangelog()` that reads `releases/changelog.json` (published by CI from `CHANGELOG.md`) and renders every version newer than the installed build, with a safe fallback to the single-note view.

**Tech Stack:** Flutter (Dart 3 records), `http` (+ `http/testing` MockClient), drift, GitHub Actions + rclone + Python (CI). Flutter binary (NOT on PATH): `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat`.

> Per-shell convenience: `$FLUTTER='%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat'`

**Branch:** `feat/resizable-chat-card` (already checked out; stay on it).

---

## File structure

| File | Responsibility |
|------|----------------|
| `lib/ui/chat/resize_math.dart` | replace `computeResize` → `computeCornerResize` (corner-aware, returns `(topLeft, size)`) |
| `lib/ui/chat/chat_overlay.dart` | fixed-height card; 4 corner grips; corner-aware resize handlers; tooltips |
| `lib/core/update/update_service.dart` | `ChangelogEntry` + `fetchChangelog()`; injectable `http.Client` |
| `lib/ui/update_dialog.dart` | scrollable multi-version changelog + single-note fallback |
| `.github/workflows/build.yml` | new step: parse `CHANGELOG.md` → upload `changelog.json` to R2 |
| `lib/core/app_version.dart`, `pubspec.yaml` | bump to `0.1.2-alpha` |
| `test/ui/chat/resize_math_test.dart` | rewrite for `computeCornerResize` |
| `test/ui/chat/chat_overlay_resize_test.dart` | rewrite: per-corner grips + tooltips |
| `test/core/update/changelog_test.dart` | **new** — `fetchChangelog` parse/filter |

`CHANGELOG.md` already exists at repo root (backfilled).

---

## Task 1: Corner-aware resize geometry

**Files:**
- Modify: `lib/ui/chat/resize_math.dart`
- Test: `test/ui/chat/resize_math_test.dart`

- [ ] **Step 1: Rewrite the test**

Replace `test/ui/chat/resize_math_test.dart` with:

```dart
import 'package:flutter/widgets.dart' show Size, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/resize_math.dart';

void main() {
  const window = Size(1000, 800); // maxW=700, maxH=680
  const startTL = Offset(100, 100);
  const startSize = Size(300, 400); // anchor rect: L=100,T=100,R=400,B=500

  test('bottom-right grip grows down-right, top-left pinned', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(50, 30),
      grip: ChatCorner.bottomRight,
      windowSize: window,
    );
    expect(r.size, const Size(350, 430));
    expect(r.topLeft, const Offset(100, 100)); // unchanged
  });

  test('top-left grip grows up-left, bottom-right pinned', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(-40, -20), // drag up-left
      grip: ChatCorner.topLeft,
      windowSize: window,
    );
    expect(r.size, const Size(340, 420));
    // bottom-right edge stays at (400,500): newLeft=400-340=60, newTop=500-420=80
    expect(r.topLeft, const Offset(60, 80));
  });

  test('top-right grip: top moves, left pinned', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(20, -10),
      grip: ChatCorner.topRight,
      windowSize: window,
    );
    expect(r.size, const Size(320, 410));
    // left pinned at 100; bottom pinned at 500 → newTop=500-410=90
    expect(r.topLeft, const Offset(100, 90));
  });

  test('bottom-left grip: left moves, top pinned', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(-30, 25),
      grip: ChatCorner.bottomLeft,
      windowSize: window,
    );
    expect(r.size, const Size(330, 425));
    // right pinned at 400 → newLeft=400-330=70; top pinned at 100
    expect(r.topLeft, const Offset(70, 100));
  });

  test('clamps to minimum and keeps the anchored corner fixed', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(-9999, -9999),
      grip: ChatCorner.topLeft,
      windowSize: window,
    );
    expect(r.size, const Size(kMinCardWidth, kMinCardHeight)); // 240,220
    // bottom-right anchor (400,500) preserved
    expect(r.topLeft, Offset(400 - kMinCardWidth, 500 - kMinCardHeight));
  });

  test('clamps to maximum fraction of window', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(9999, 9999),
      grip: ChatCorner.bottomRight,
      windowSize: window,
    );
    expect(r.size, Size(window.width * kMaxCardWidthFrac, window.height * kMaxCardHeightFrac));
    expect(r.topLeft, const Offset(100, 100));
  });
}
```

- [ ] **Step 2: Run the test — expect FAIL**

Run: `$FLUTTER test test/ui/chat/resize_math_test.dart`
Expected: FAIL — `computeCornerResize` undefined.

- [ ] **Step 3: Replace the implementation**

Replace the entire contents of `lib/ui/chat/resize_math.dart` with:

```dart
import 'dart:ui' show Size, Offset;

import 'chat_corner.dart';

/// Smallest usable card size, in logical px.
const double kMinCardWidth = 240;
const double kMinCardHeight = 220;

/// Largest card size, as a fraction of the window.
const double kMaxCardWidthFrac = 0.70;
const double kMaxCardHeightFrac = 0.85;

/// New top-left + size from dragging one corner [grip] of the card.
///
/// The corner opposite [grip] is the anchor and stays fixed; the dragged corner
/// follows the accumulated [dragDelta]. Width/height are clamped to the min/max
/// bounds, and the position is recomputed from the fixed edge AFTER clamping so
/// the anchored corner never drifts. The card free-floats during the drag, so
/// growth direction is encoded by which corner is grabbed.
({Offset topLeft, Size size}) computeCornerResize({
  required Offset startTopLeft,
  required Size startSize,
  required Offset dragDelta,
  required ChatCorner grip,
  required Size windowSize,
}) {
  final maxW = windowSize.width * kMaxCardWidthFrac;
  final maxH = windowSize.height * kMaxCardHeightFrac;

  final isRight = grip == ChatCorner.topRight || grip == ChatCorner.bottomRight;
  final isBottom =
      grip == ChatCorner.bottomLeft || grip == ChatCorner.bottomRight;

  final double newWidth;
  final double newLeft;
  if (isRight) {
    newWidth = (startSize.width + dragDelta.dx).clamp(kMinCardWidth, maxW);
    newLeft = startTopLeft.dx;
  } else {
    final rightEdge = startTopLeft.dx + startSize.width;
    newWidth = (startSize.width - dragDelta.dx).clamp(kMinCardWidth, maxW);
    newLeft = rightEdge - newWidth;
  }

  final double newHeight;
  final double newTop;
  if (isBottom) {
    newHeight = (startSize.height + dragDelta.dy).clamp(kMinCardHeight, maxH);
    newTop = startTopLeft.dy;
  } else {
    final bottomEdge = startTopLeft.dy + startSize.height;
    newHeight = (startSize.height - dragDelta.dy).clamp(kMinCardHeight, maxH);
    newTop = bottomEdge - newHeight;
  }

  return (topLeft: Offset(newLeft, newTop), size: Size(newWidth, newHeight));
}
```

- [ ] **Step 4: Run the test — expect PASS (6 tests)**

Run: `$FLUTTER test test/ui/chat/resize_math_test.dart`
Then: `$FLUTTER analyze lib/ui/chat/resize_math.dart` → `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/ui/chat/resize_math.dart test/ui/chat/resize_math_test.dart
git commit -m "feat: corner-aware computeCornerResize (4-corner resize geometry)"
```

---

## Task 2: Fixed-height card, four corner grips, tooltips

**Files:**
- Modify: `lib/ui/chat/chat_overlay.dart`
- Test: `test/ui/chat/chat_overlay_resize_test.dart`

Read `lib/ui/chat/chat_overlay.dart` fully first. Current relevant shape:
- `_ChatOverlayState` has `_startResize()`/`_updateResize(Offset)`/`_endResize()` (single bottom-right grip, using `computeResize`) plus fields `_resizeStartSize`, `_resizeDelta`.
- `_buildCard` passes `width`/`maxHeight` and `onResizeStart`/`onResizeUpdate`/`onResizeEnd` to `_GlassCard`.
- `_GlassCard` has `width`, `maxHeight`; its `build` returns a `Stack` whose first child is the `DecoratedBox(... Container(width:..., constraints: BoxConstraints(maxHeight:...), child: Column(mainAxisSize: min, [header, Flexible(messages), typing, ChatInput])))` and whose second child is a single bottom-right grip `Positioned` keyed `chat-resize-grip`.

- [ ] **Step 1: Rewrite the widget test**

Replace `test/ui/chat/chat_overlay_resize_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/chat_overlay.dart';

Widget _host({
  required void Function(Size) onResize,
  required VoidCallback onResetSize,
}) =>
    MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ChatOverlay(
          messages: const [],
          myUsername: 'me',
          collapsed: false,
          corner: ChatCorner.bottomLeft,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
          onResize: onResize,
          onResetSize: onResetSize,
        ),
      ),
    );

void main() {
  testWidgets('reset button fires onResetSize', (tester) async {
    var reset = false;
    await tester.pumpWidget(_host(onResize: (_) {}, onResetSize: () => reset = true));
    await tester.tap(find.byKey(const ValueKey('chat-reset-size')));
    await tester.pump();
    expect(reset, isTrue);
  });

  testWidgets('has a grip at each corner', (tester) async {
    await tester.pumpWidget(_host(onResize: (_) {}, onResetSize: () {}));
    for (final c in ChatCorner.values) {
      expect(find.byKey(ValueKey('chat-resize-grip-${c.name}')), findsOneWidget);
    }
  });

  testWidgets('dragging each corner grip reports a new size', (tester) async {
    for (final c in ChatCorner.values) {
      Size? got;
      await tester.pumpWidget(_host(onResize: (s) => got = s, onResetSize: () {}));
      await tester.drag(
          find.byKey(ValueKey('chat-resize-grip-${c.name}')), const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(got, isNotNull, reason: 'grip ${c.name} should report size');
    }
  });

  testWidgets('control tooltips are present', (tester) async {
    await tester.pumpWidget(_host(onResize: (_) {}, onResetSize: () {}));
    expect(find.byTooltip('Reset size'), findsOneWidget);
    expect(find.byTooltip('Hide chat'), findsOneWidget);
    expect(find.byTooltip('Drag to move'), findsOneWidget);
    expect(find.byTooltip('Drag to resize'), findsWidgets); // one per corner
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`chat-resize-grip-*` keys & tooltips don't exist)

Run: `$FLUTTER test test/ui/chat/chat_overlay_resize_test.dart`

- [ ] **Step 3: Make resize handlers corner-aware in `_ChatOverlayState`**

Replace the three resize fields/methods. First, the fields — replace:
```dart
  Size? _resizeStartSize;
  Offset _resizeDelta = Offset.zero;
```
with:
```dart
  Size? _resizeStartSize;
  Offset? _resizeStartTopLeft;
  Offset _resizeDelta = Offset.zero;
  ChatCorner _resizeGrip = ChatCorner.bottomRight;
```
Then replace the `_startResize()`, `_updateResize(...)`, `_endResize()` methods with:
```dart
  /// Begin a grip resize from corner [grip]: pin the card's current rect and
  /// remember which corner is being dragged.
  void _startResize(ChatCorner grip) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    final cardBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (cardBox == null || selfBox == null) return;
    final origin = selfBox.localToGlobal(Offset.zero);
    final topLeft = cardBox.localToGlobal(Offset.zero) - origin;
    setState(() {
      _dragTopLeft = topLeft;
      _dragCardSize = cardBox.size;
      _overlaySize = selfBox.size;
      _resizeStartSize = cardBox.size;
      _resizeStartTopLeft = topLeft;
      _resizeDelta = Offset.zero;
      _resizeGrip = grip;
    });
    widget.onDraggingChanged?.call(true);
  }

  void _updateResize(Offset delta) {
    final start = _resizeStartSize;
    final startTL = _resizeStartTopLeft;
    final window = _overlaySize;
    if (start == null || startTL == null || window == null) return;
    _resizeDelta += delta;
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: start,
      dragDelta: _resizeDelta,
      grip: _resizeGrip,
      windowSize: window,
    );
    setState(() {
      _dragTopLeft = r.topLeft;
      _dragCardSize = r.size;
    });
  }

  /// End the resize: report the new size, then glide back to the docked corner.
  void _endResize() {
    final size = _dragCardSize;
    final topLeft = _dragTopLeft;
    final window = _overlaySize;
    _resizeStartSize = null;
    _resizeStartTopLeft = null;
    _resizeDelta = Offset.zero;
    if (size == null || topLeft == null || window == null) {
      _clearDrag();
      return;
    }
    widget.onResize?.call(size);
    _snapFrom = topLeft;
    _snapTo = _cornerTopLeft(widget.corner, size, window);
    _snapCtrl.forward(from: 0);
  }
```

- [ ] **Step 4: Update `_buildCard` to pass a fixed height + corner-aware start**

In `_buildCard`, change `maxHeight: cardSize.height,` to `height: cardSize.height,` and change `onResizeStart: _startResize,` to `onResizeStart: _startResize,` is already a tear-off but now takes a `ChatCorner` — keep it as `onResizeStart: _startResize,` (the tear-off matches the new `void Function(ChatCorner)` signature). Final `_buildCard` `_GlassCard(...)` args for these fields read:
```dart
        width: cardSize.width,
        height: cardSize.height,
        ...
        onResetSize: widget.onResetSize ?? () {},
        onResizeStart: _startResize,
        onResizeUpdate: _updateResize,
        onResizeEnd: _endResize,
```

- [ ] **Step 5: `_GlassCard` — fixed height, Expanded messages, 4 grips, tooltips**

In `_GlassCard`:
- Rename the constructor param and field `maxHeight` → `height`:
  - constructor: `required this.height,`
  - field: `final double height;`
- Change `onResizeStart` field type from `VoidCallback` to `void Function(ChatCorner corner)`:
  ```dart
  final void Function(ChatCorner corner) onResizeStart;
  ```
- In `build`, change the inner `Container`:
  ```dart
            Container(
              width: width,
              height: height,
  ```
  (remove the `constraints: BoxConstraints(maxHeight: maxHeight),` line entirely).
- Change the `Column(mainAxisSize: MainAxisSize.min, ...)` to fill the fixed height: remove `mainAxisSize: MainAxisSize.min,` (defaults to `MainAxisSize.max`).
- Replace the message `Flexible(child: messages.isEmpty ? Padding(...) : ListView(shrinkWrap: true, ...))` with an `Expanded` that fills + scrolls:
  ```dart
                  Expanded(
                    child: messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 24),
                              child: Text(
                                'No messages yet — say hi 🐾',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: m.textDim, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: [
                              for (final msg in messages)
                                ChatBubble(message: msg, myUsername: myUsername),
                            ],
                          ),
                  ),
  ```
- Wrap the three header controls in tooltips:
  - The drag handle icon: change `Icon(Icons.drag_indicator, size: 16, color: m.textDim)` to
    ```dart
    Tooltip(
      message: 'Drag to move',
      child: Icon(Icons.drag_indicator, size: 16, color: m.textDim),
    )
    ```
  - The reset button: wrap its `Icon(Icons.crop_free, ...)` in `Tooltip(message: 'Reset size', child: ...)`.
  - The collapse button: wrap its `Icon(Icons.chevron_right, ...)` in `Tooltip(message: 'Hide chat', child: ...)`.
- Replace the single bottom-right grip `Positioned(...)` (the second child of the outer `Stack`) with four corner grips. Add this helper method to `_GlassCard` (above `build`):
  ```dart
  Widget _grip(BuildContext context, ChatCorner corner) {
    final m = context.meow;
    return GestureDetector(
      key: ValueKey('chat-resize-grip-${corner.name}'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (_) => onResizeStart(corner),
      onPanUpdate: (d) => onResizeUpdate(d.delta),
      onPanEnd: (_) => onResizeEnd(),
      child: Tooltip(
        message: 'Drag to resize',
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.open_in_full, size: 14, color: m.accent),
        ),
      ),
    );
  }
  ```
  And replace the old single `Positioned(...)` grip with these four (as the remaining children of the outer `Stack`, after the `DecoratedBox`):
  ```dart
        Positioned(left: 0, top: 0, child: _grip(context, ChatCorner.topLeft)),
        Positioned(right: 0, top: 0, child: _grip(context, ChatCorner.topRight)),
        Positioned(
            left: 0, bottom: 0, child: _grip(context, ChatCorner.bottomLeft)),
        Positioned(
            right: 0, bottom: 0, child: _grip(context, ChatCorner.bottomRight)),
  ```

- [ ] **Step 6: Run the widget test — expect PASS (4 tests)**

Run: `$FLUTTER test test/ui/chat/chat_overlay_resize_test.dart`

- [ ] **Step 7: Analyze + full suite (goldens)**

Run: `$FLUTTER analyze lib/ui/chat/chat_overlay.dart` → `No issues found!`
Run: `$FLUTTER test`
If a chat golden fails because the header/grips changed the rendered card, regenerate and inspect:
`$FLUTTER test test/ui/chat/chat_overlay_golden_test.dart --update-goldens`
then open the PNG(s) under `test/ui/chat/goldens/` and confirm they look right.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/chat/chat_overlay.dart test/ui/chat/chat_overlay_resize_test.dart test/ui/chat/goldens
git commit -m "feat: four-corner resize, fixed-height card, button tooltips"
```

---

## Task 3: UpdateService.fetchChangelog

**Files:**
- Modify: `lib/core/update/update_service.dart`
- Test: `test/core/update/changelog_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `test/core/update/changelog_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meowwatch/core/update/update_service.dart';

void main() {
  test('fetchChangelog returns only versions newer than the installed build', () async {
    final body = jsonEncode([
      {'version': '9.9.9', 'date': '2099-01-01', 'notes': '- future stuff'},
      {'version': '0.0.1', 'date': '2000-01-01', 'notes': '- ancient'},
    ]);
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('changelog.json')) {
        return http.Response(body, 200);
      }
      return http.Response('', 404);
    });
    final svc = UpdateService(baseUrl: 'https://example.test', client: mock);

    final entries = await svc.fetchChangelog();

    expect(entries.map((e) => e.version), contains('9.9.9'));
    expect(entries.map((e) => e.version), isNot(contains('0.0.1')));
    expect(entries.first.notes, contains('future stuff'));
  });

  test('fetchChangelog returns empty list on a 404', () async {
    final mock = MockClient((req) async => http.Response('', 404));
    final svc = UpdateService(baseUrl: 'https://example.test', client: mock);
    expect(await svc.fetchChangelog(), isEmpty);
  });

  test('fetchChangelog returns empty list on malformed JSON', () async {
    final mock = MockClient((req) async => http.Response('not json', 200));
    final svc = UpdateService(baseUrl: 'https://example.test', client: mock);
    expect(await svc.fetchChangelog(), isEmpty);
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`client:` param & `fetchChangelog`/`ChangelogEntry` missing)

Run: `$FLUTTER test test/core/update/changelog_test.dart`

- [ ] **Step 3: Implement**

In `lib/core/update/update_service.dart`:

Change the constructor + client field so a client can be injected (find the current `UpdateService({String? baseUrl}) : _baseUrl = baseUrl ?? updateBaseUrl;` and `final http.Client _client = http.Client();`) and replace with:
```dart
  UpdateService({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? updateBaseUrl,
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
```

Add the entry type near `UpdateInfo` (top-level, after the `UpdateInfo` class):
```dart
/// One version's changelog entry, as published in `releases/changelog.json`.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.notes,
  });

  final String version;
  final String date;
  final String notes;
}
```

Add the method inside `UpdateService` (e.g. just after `checkForUpdate`):
```dart
  /// Fetch the multi-version changelog and return only the entries newer than
  /// the installed [appVersion], newest first. Returns an empty list on any
  /// failure (missing file, network error, malformed JSON) so callers can fall
  /// back to the single-release note.
  Future<List<ChangelogEntry>> fetchChangelog() async {
    try {
      final uri = Uri.parse('$_baseUrl/releases/changelog.json');
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];

      final list = jsonDecode(response.body) as List<dynamic>;
      final entries = <ChangelogEntry>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final version = item['version'] as String?;
        if (version == null) continue;
        if (!_isNewer(version, appVersion)) continue;
        entries.add(ChangelogEntry(
          version: version,
          date: (item['date'] as String?) ?? '',
          notes: (item['notes'] as String?) ?? '',
        ));
      }
      return entries;
    } on Exception {
      return const [];
    }
  }
```
(`jsonDecode` from `dart:convert` and `http` are already imported in this file. `_isNewer` and `appVersion` already exist.)

- [ ] **Step 4: Run — expect PASS (3 tests)**

Run: `$FLUTTER test test/core/update/changelog_test.dart`
Run: `$FLUTTER analyze lib/core/update/update_service.dart` → `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/update/update_service.dart test/core/update/changelog_test.dart
git commit -m "feat: UpdateService.fetchChangelog reads multi-version changelog from R2"
```

---

## Task 4: Scrollable changelog in the update dialog

**Files:**
- Modify: `lib/ui/update_dialog.dart`

No new unit test (UI wiring; covered by manual test). Keep the change minimal.

- [ ] **Step 1: Hold the fetched changelog in state**

In `_UpdateDialogState`, add a field near `_downloadProgress`:
```dart
  List<ChangelogEntry> _changelog = const [];
```

- [ ] **Step 2: Fetch it when an update is available**

In `_checkForUpdate`, change the `updateAvailable` case to also fetch the changelog:
```dart
      case UpdateStatus.updateAvailable:
        final changelog = await _service.fetchChangelog();
        if (!mounted) return;
        setState(() {
          _changelog = changelog;
          _phase = _UpdatePhase.updateAvailable;
        });
```

- [ ] **Step 3: Render the scrollable list (with fallback)**

In `_buildBody`, inside `case _UpdatePhase.updateAvailable:`, replace the existing single-note block:
```dart
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (m.background as Color).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (m.border as Color).withValues(alpha: 0.5)),
                ),
                child: Text(
                  info.releaseNotes,
                  style: TextStyle(color: m.textDim as Color, fontSize: 12),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
```
with:
```dart
            if (_changelog.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (m.background as Color).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (m.border as Color).withValues(alpha: 0.5)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _changelog.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 16,
                    color: (m.border as Color).withValues(alpha: 0.4),
                  ),
                  itemBuilder: (context, i) {
                    final e = _changelog[i];
                    final header =
                        e.date.isEmpty ? 'v${e.version}' : 'v${e.version} · ${e.date}';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          header,
                          style: TextStyle(
                            color: m.textPrimary as Color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.notes,
                          style: TextStyle(color: m.textDim as Color, fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ] else if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (m.background as Color).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (m.border as Color).withValues(alpha: 0.5)),
                ),
                child: Text(
                  info.releaseNotes,
                  style: TextStyle(color: m.textDim as Color, fontSize: 12),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
```

- [ ] **Step 4: Analyze + full suite**

Run: `$FLUTTER analyze lib/ui/update_dialog.dart` → `No issues found!`
Run: `$FLUTTER test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/update_dialog.dart
git commit -m "feat: scrollable multi-version changelog in the update dialog"
```

---

## Task 5: CI publishes changelog.json to R2

**Files:**
- Modify: `.github/workflows/build.yml`

- [ ] **Step 1: Add the publish step**

In `.github/workflows/build.yml`, immediately AFTER the existing `- name: Update latest.json on R2` step (the last step in the `release` job), add:

```yaml
      - name: Publish changelog to R2
        run: |
          python3 - <<'PY'
          import json, re, pathlib
          path = pathlib.Path('CHANGELOG.md')
          text = path.read_text(encoding='utf-8') if path.exists() else ''
          header = re.compile(r'^## \[(?P<v>[^\]]+)\]\s*-\s*(?P<d>.+)$')
          entries = []
          cur = None
          for line in text.splitlines():
              mobj = header.match(line.strip())
              if mobj:
                  if cur:
                      entries.append(cur)
                  cur = {'version': mobj.group('v').strip(),
                         'date': mobj.group('d').strip(), 'notes': ''}
              elif cur is not None:
                  cur['notes'] += line + '\n'
          if cur:
              entries.append(cur)
          for e in entries:
              e['notes'] = e['notes'].strip()
          pathlib.Path('changelog.json').write_text(
              json.dumps(entries, ensure_ascii=False, indent=2), encoding='utf-8')
          print(f'{len(entries)} changelog entries')
          PY
          rclone copyto changelog.json r2:${{ secrets.R2_BUCKET_NAME }}/releases/changelog.json
```

- [ ] **Step 2: Validate the YAML + the parser locally**

Validate the parser logic against the real `CHANGELOG.md` (Windows has Python; if `python3` is missing use `python`):
```bash
python - <<'PY'
import json, re, pathlib
text = pathlib.Path('CHANGELOG.md').read_text(encoding='utf-8')
header = re.compile(r'^## \[(?P<v>[^\]]+)\]\s*-\s*(?P<d>.+)$')
entries=[]; cur=None
for line in text.splitlines():
    mobj = header.match(line.strip())
    if mobj:
        if cur: entries.append(cur)
        cur={'version':mobj.group('v').strip(),'date':mobj.group('d').strip(),'notes':''}
    elif cur is not None:
        cur['notes'] += line+'\n'
if cur: entries.append(cur)
for e in entries: e['notes']=e['notes'].strip()
print(json.dumps(entries, ensure_ascii=False, indent=2))
PY
```
Expected: a 3-element JSON array (0.1.2-alpha, 0.1.1-alpha, 0.1.0-alpha) each with `version`, `date`, and multi-line `notes`. Eyeball it.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: publish CHANGELOG.md as changelog.json to R2 on release"
```

---

## Task 6: Version bump

**Files:**
- Modify: `lib/core/app_version.dart`, `pubspec.yaml`

- [ ] **Step 1: Bump**

In `lib/core/app_version.dart`: `const String appVersion = '0.1.1-alpha';` → `'0.1.2-alpha';`
In `pubspec.yaml`: `version: 0.1.1-alpha+1` → `version: 0.1.2-alpha+1`

- [ ] **Step 2: Full suite + analyze**

Run: `$FLUTTER analyze` → `No issues found!`
Run: `$FLUTTER test` → all pass.

- [ ] **Step 3: Commit**

```bash
git add lib/core/app_version.dart pubspec.yaml
git commit -m "chore: bump to 0.1.2-alpha"
```

---

## Task 7: Manual test, merge, release

- [ ] **Step 1: Build the Release (kill running instances first)**

```powershell
Stop-Process -Name meowwatch -Force -ErrorAction SilentlyContinue
%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat build windows
```

- [ ] **Step 2: Manual two-instance test**

Launch `build/windows/x64/runner/Release/meowwatch.exe` and verify:
- Resize from each of the four corners; the opposite corner stays put; height visibly changes; the card re-docks to its corner on release; clamps at min/max.
- Hover shows tooltips on the drag handle, reset, collapse, and grips.
- Reset still restores default size; resized size persists across relaunch.
- Card still drags between corners, collapses to the peek tab, chat works.

STOP here and report to the user for confirmation before merging/releasing (per CLAUDE.md: don't tag complete until a manual two-instance test passes).

- [ ] **Step 3: After user confirms — merge to main**

```bash
git checkout main
git merge --no-ff feat/resizable-chat-card -m "feat: resizable chat card (four-corner) + multi-version changelog updater"
git push
```

- [ ] **Step 4: Tag the release (fires the R2 pipeline incl. changelog.json)**

```bash
git tag v0.1.2-alpha
git push origin v0.1.2-alpha
```

- [ ] **Step 5: Verify R2 after the Build workflow's release job is green**

```bash
curl -s https://pub-6002641cc8a44c128f0684981b511991.r2.dev/releases/latest.json
curl -s https://pub-6002641cc8a44c128f0684981b511991.r2.dev/releases/changelog.json
```
Expected: `latest.json` version `0.1.2-alpha`; `changelog.json` an array including 0.1.2-alpha / 0.1.1-alpha / 0.1.0-alpha.

- [ ] **Step 6: End-to-end update test**

Open a still-installed older build that has the correct r2.dev URL (e.g. the 0.1.0-alpha or 0.1.1-alpha zip). The updater should detect 0.1.2-alpha and show a scrollable changelog listing every version newer than the installed one; download + install applies the update.

---

## Self-review notes

- Spec coverage: fixed height (Task 2/A1), `computeCornerResize` 4-corner geometry (Task 1/A2), tooltips (Task 2/A3), `CHANGELOG.md` source (already committed; parsed in Task 5/B1-B2), `fetchChangelog` newer-than-installed filter (Task 3/B3), scrollable dialog + fallback (Task 4/B4), version bump (Task 6), release/E2E (Task 7) — all covered.
- Names consistent across tasks: `computeCornerResize` returns `({Offset topLeft, Size size})`; `_GlassCard.height` (renamed from `maxHeight`); grip keys `chat-resize-grip-<corner.name>`; `ChangelogEntry(version,date,notes)`; `fetchChangelog()`; `UpdateService({baseUrl, client})`.
- The single-grip key `chat-resize-grip` is intentionally removed in favor of per-corner keys; the rewritten widget test no longer references the old key.
- `_GlassCard.onResizeStart` signature changes `VoidCallback` → `void Function(ChatCorner)`; the `_startResize` tear-off in `_buildCard` matches the new signature.
