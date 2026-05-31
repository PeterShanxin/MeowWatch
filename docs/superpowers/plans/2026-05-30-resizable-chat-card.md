# Resizable Chat Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user drag-resize the floating chat card, reset it to default, and have the chosen size persist across launches.

**Architecture:** Pure resize math (`computeResize`) split from the widget like the existing `computeSnap`. Size is held as window fractions on the immutable `ChatOverlayLayout`, rendered as px at build time. During a grip drag the card free-floats top-left-pinned (reusing the existing `_dragTopLeft` render path) and eases back to its docked corner on release. Persistence reuses the existing `SettingsStore` key/value store (same path the theme uses).

**Tech Stack:** Flutter (Dart), `media_kit` (unrelated here), drift `SettingsStore`. Flutter binary: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat` (NOT on PATH).

> Set once per shell: `$FLUTTER='C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat'`

---

## File structure

| File | Responsibility |
|------|----------------|
| `lib/ui/chat/resize_math.dart` | **new** — pure `computeResize` + bound consts |
| `lib/ui/chat/chat_overlay_layout.dart` | size fractions + `applyResize`/`resetSize` + parse/format helpers |
| `lib/core/data/settings_store.dart` | add `kChatCardSizeSettingKey` |
| `lib/ui/chat/chat_overlay.dart` | grip + reset button; render size from fractions; resize callbacks |
| `lib/ui/home_screen.dart` | seed layout from initial size; persist on resize/reset |
| `lib/app.dart` | thread `settings` + `initialCardSize` to `HomeScreen` |
| `lib/main.dart` | load `chat_card_size` setting at startup |
| `lib/core/app_version.dart`, `pubspec.yaml` | bump to `0.1.1-alpha` |
| `test/ui/chat/resize_math_test.dart` | **new** |
| `test/ui/chat/chat_overlay_layout_test.dart` | extend |
| `docs/ROADMAP.md` | note the feature |

---

## Task 1: Pure resize math

**Files:**
- Create: `lib/ui/chat/resize_math.dart`
- Test: `test/ui/chat/resize_math_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/chat/resize_math_test.dart`:

```dart
import 'package:flutter/widgets.dart' show Size, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/resize_math.dart';

void main() {
  const window = Size(1000, 800); // maxW=700, maxH=680
  const start = Size(300, 400);

  test('grows width and height with positive delta', () {
    final r = computeResize(
      startSize: start,
      dragDelta: const Offset(50, 30),
      windowSize: window,
    );
    expect(r.width, 350);
    expect(r.height, 430);
  });

  test('shrinks with negative delta', () {
    final r = computeResize(
      startSize: start,
      dragDelta: const Offset(-40, -20),
      windowSize: window,
    );
    expect(r.width, 260);
    expect(r.height, 380);
  });

  test('clamps to minimum size', () {
    final r = computeResize(
      startSize: start,
      dragDelta: const Offset(-500, -500),
      windowSize: window,
    );
    expect(r.width, kMinCardWidth);
    expect(r.height, kMinCardHeight);
  });

  test('clamps to maximum fraction of window', () {
    final r = computeResize(
      startSize: start,
      dragDelta: const Offset(9999, 9999),
      windowSize: window,
    );
    expect(r.width, window.width * kMaxCardWidthFrac); // 700
    expect(r.height, window.height * kMaxCardHeightFrac); // 680
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/ui/chat/resize_math_test.dart`
Expected: FAIL — `resize_math.dart` / `computeResize` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/chat/resize_math.dart`:

```dart
import 'dart:ui' show Size, Offset;

/// Smallest usable card size, in logical px.
const double kMinCardWidth = 240;
const double kMinCardHeight = 220;

/// Largest card size, as a fraction of the window.
const double kMaxCardWidthFrac = 0.70;
const double kMaxCardHeightFrac = 0.85;

/// New card size from a bottom-right grip drag.
///
/// The card free-floats top-left-pinned during the drag, so a positive delta
/// always grows the card right/down regardless of which corner it docks to.
/// Result is clamped to [kMinCardWidth]/[kMinCardHeight] and to
/// [kMaxCardWidthFrac]/[kMaxCardHeightFrac] of [windowSize].
Size computeResize({
  required Size startSize,
  required Offset dragDelta,
  required Size windowSize,
}) {
  final maxW = windowSize.width * kMaxCardWidthFrac;
  final maxH = windowSize.height * kMaxCardHeightFrac;
  final w = (startSize.width + dragDelta.dx).clamp(kMinCardWidth, maxW);
  final h = (startSize.height + dragDelta.dy).clamp(kMinCardHeight, maxH);
  return Size(w, h);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/ui/chat/resize_math_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/chat/resize_math.dart test/ui/chat/resize_math_test.dart
git commit -m "feat: add pure computeResize geometry for chat card"
```

---

## Task 2: Size fractions on ChatOverlayLayout + persistence helpers

**Files:**
- Modify: `lib/ui/chat/chat_overlay_layout.dart`
- Modify: `lib/core/data/settings_store.dart`
- Test: `test/ui/chat/chat_overlay_layout_test.dart`

- [ ] **Step 1: Add the settings key**

In `lib/core/data/settings_store.dart`, below `kThemeSettingKey`, add:

```dart
/// Key for the persisted chat-card size (value = "<widthFrac>,<heightFrac>",
/// or empty string for the default size).
const String kChatCardSizeSettingKey = 'chat_card_size';
```

- [ ] **Step 2: Write the failing test**

Create/replace `test/ui/chat/chat_overlay_layout_test.dart`:

```dart
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/chat_overlay_layout.dart';

void main() {
  test('defaults have null size fractions', () {
    const l = ChatOverlayLayout();
    expect(l.widthFrac, isNull);
    expect(l.heightFrac, isNull);
  });

  test('applyResize derives fractions from px over window', () {
    const l = ChatOverlayLayout();
    final r = l.applyResize(const Size(300, 400), const Size(1000, 800));
    expect(r.widthFrac, closeTo(0.30, 1e-9));
    expect(r.heightFrac, closeTo(0.50, 1e-9));
  });

  test('resetSize clears fractions but keeps corner', () {
    final l = const ChatOverlayLayout(corner: ChatCorner.topRight)
        .applyResize(const Size(500, 600), const Size(1000, 800));
    final r = l.resetSize();
    expect(r.widthFrac, isNull);
    expect(r.heightFrac, isNull);
    expect(r.corner, ChatCorner.topRight);
  });

  test('format and parse round-trip', () {
    expect(formatCardSizeFraction(0.42, 0.63), '0.42,0.63');
    expect(parseCardSizeFraction('0.42,0.63'), (0.42, 0.63));
  });

  test('parse returns nulls for empty or malformed input', () {
    expect(parseCardSizeFraction(null), (null, null));
    expect(parseCardSizeFraction(''), (null, null));
    expect(parseCardSizeFraction('garbage'), (null, null));
    expect(parseCardSizeFraction('1.5,0.5'), (null, null)); // out of range
  });

  test('equality includes size fractions', () {
    final a = const ChatOverlayLayout()
        .applyResize(const Size(300, 400), const Size(1000, 800));
    final b = const ChatOverlayLayout()
        .applyResize(const Size(300, 400), const Size(1000, 800));
    expect(a, b);
    expect(a, isNot(const ChatOverlayLayout()));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `$FLUTTER test test/ui/chat/chat_overlay_layout_test.dart`
Expected: FAIL — `widthFrac`, `applyResize`, `formatCardSizeFraction`, etc. undefined.

- [ ] **Step 4: Write the implementation**

Replace `lib/ui/chat/chat_overlay_layout.dart` with:

```dart
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'chat_corner.dart';

/// Immutable placement + size state for the chat card.
@immutable
class ChatOverlayLayout {
  const ChatOverlayLayout({
    this.corner = ChatCorner.bottomLeft,
    this.collapsed = false,
    this.lastCorner = ChatCorner.bottomLeft,
    this.widthFrac,
    this.heightFrac,
  });

  final ChatCorner corner;
  final bool collapsed;
  final ChatCorner lastCorner;

  /// Card width/height as a fraction (0..1) of the window. Null = use default.
  final double? widthFrac;
  final double? heightFrac;

  ChatOverlayLayout copyWith({
    ChatCorner? corner,
    bool? collapsed,
    ChatCorner? lastCorner,
    double? widthFrac,
    double? heightFrac,
  }) =>
      ChatOverlayLayout(
        corner: corner ?? this.corner,
        collapsed: collapsed ?? this.collapsed,
        lastCorner: lastCorner ?? this.lastCorner,
        widthFrac: widthFrac ?? this.widthFrac,
        heightFrac: heightFrac ?? this.heightFrac,
      );

  /// Apply a drag-release result: snap to a corner, or collapse (remembering
  /// the current corner so [toggle] can restore it).
  ChatOverlayLayout applySnap(SnapResult result) {
    if (result.collapsed) {
      return copyWith(collapsed: true, lastCorner: corner);
    }
    return copyWith(corner: result.corner, collapsed: false);
  }

  /// Collapse↔expand. Collapsing remembers the corner; expanding restores it.
  ChatOverlayLayout toggle() {
    if (collapsed) {
      return copyWith(collapsed: false, corner: lastCorner);
    }
    return copyWith(collapsed: true, lastCorner: corner);
  }

  /// Record a new px size as fractions of [window].
  ChatOverlayLayout applyResize(Size px, Size window) => copyWith(
        widthFrac: px.width / window.width,
        heightFrac: px.height / window.height,
      );

  /// Clear the custom size (back to the default fractions).
  ChatOverlayLayout resetSize() => ChatOverlayLayout(
        corner: corner,
        collapsed: collapsed,
        lastCorner: lastCorner,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatOverlayLayout &&
      other.corner == corner &&
      other.collapsed == collapsed &&
      other.lastCorner == lastCorner &&
      other.widthFrac == widthFrac &&
      other.heightFrac == heightFrac;

  @override
  int get hashCode =>
      Object.hash(corner, collapsed, lastCorner, widthFrac, heightFrac);
}

/// Serialize size fractions for [kChatCardSizeSettingKey] storage.
String formatCardSizeFraction(double widthFrac, double heightFrac) =>
    '$widthFrac,$heightFrac';

/// Parse a stored size value into (widthFrac, heightFrac). Returns (null, null)
/// for missing, empty, malformed, or out-of-range (0..1) values.
(double?, double?) parseCardSizeFraction(String? value) {
  if (value == null || value.isEmpty) return (null, null);
  final parts = value.split(',');
  if (parts.length != 2) return (null, null);
  final w = double.tryParse(parts[0]);
  final h = double.tryParse(parts[1]);
  if (w == null || h == null) return (null, null);
  if (w <= 0 || w > 1 || h <= 0 || h > 1) return (null, null);
  return (w, h);
}
```

> Note: `copyWith` cannot null-out fields (the `??` keeps the old value), so
> `resetSize` builds a fresh instance to clear the fractions.

- [ ] **Step 5: Run test to verify it passes**

Run: `$FLUTTER test test/ui/chat/chat_overlay_layout_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/chat/chat_overlay_layout.dart lib/core/data/settings_store.dart test/ui/chat/chat_overlay_layout_test.dart
git commit -m "feat: add card size fractions + persistence helpers to chat layout"
```

---

## Task 3: Resize grip + reset button in ChatOverlay

**Files:**
- Modify: `lib/ui/chat/chat_overlay.dart`
- Test: `test/ui/chat/chat_overlay_resize_test.dart` (new)

This task renders the card size from fractions, adds a bottom-right resize grip
(free-floating top-left-pinned during the drag, re-docking on release), and a
reset button in the header. The grip reuses the existing `_dragTopLeft` /
`_snapCtrl` glide machinery.

- [ ] **Step 1: Write the failing widget test**

Create `test/ui/chat/chat_overlay_resize_test.dart`:

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

  testWidgets('dragging the grip reports a new size', (tester) async {
    Size? got;
    await tester.pumpWidget(_host(onResize: (s) => got = s, onResetSize: () {}));
    final grip = find.byKey(const ValueKey('chat-resize-grip'));
    expect(grip, findsOneWidget);
    await tester.drag(grip, const Offset(40, 30));
    await tester.pumpAndSettle();
    expect(got, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/ui/chat/chat_overlay_resize_test.dart`
Expected: FAIL — `onResize`/`onResetSize` params and the keyed widgets don't exist.

- [ ] **Step 3: Add the widget params and callbacks**

In `lib/ui/chat/chat_overlay.dart`, add the import at the top (with the other
chat imports):

```dart
import 'resize_math.dart';
```

In the `ChatOverlay` constructor, add the new params (after `onSnap`):

```dart
    required this.onResize,
    required this.onResetSize,
    this.widthFrac,
    this.heightFrac,
```

And the matching fields (after `onSnap`'s field):

```dart
  /// Reports the card's new px size when a resize grip drag ends.
  final void Function(Size newSize) onResize;

  /// Resets the card to its default size.
  final VoidCallback onResetSize;

  /// Card size as a fraction of the window; null falls back to 0.30 / 0.50.
  final double? widthFrac;
  final double? heightFrac;
```

- [ ] **Step 4: Add resize state + handlers to `_ChatOverlayState`**

After the existing drag fields (near `_dragTopLeft` / `_dragCardSize`), add:

```dart
  // Active resize: size captured at grip-drag start + accumulated grip delta.
  Size? _resizeStartSize;
  Offset _resizeDelta = Offset.zero;
```

Add these methods to `_ChatOverlayState` (next to `_startHeaderDrag`):

```dart
  /// Begin a grip resize: pin the card's current top-left (free-float) and
  /// capture its current rendered size to grow from.
  void _startResize() {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    final cardBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (cardBox == null || selfBox == null) return;
    final origin = selfBox.localToGlobal(Offset.zero);
    setState(() {
      _dragTopLeft = cardBox.localToGlobal(Offset.zero) - origin;
      _dragCardSize = cardBox.size;
      _overlaySize = selfBox.size;
      _resizeStartSize = cardBox.size;
      _resizeDelta = Offset.zero;
    });
    widget.onDraggingChanged?.call(true);
  }

  void _updateResize(Offset delta) {
    final start = _resizeStartSize;
    final window = _overlaySize;
    if (start == null || window == null) return;
    _resizeDelta += delta;
    setState(() {
      _dragCardSize = computeResize(
        startSize: start,
        dragDelta: _resizeDelta,
        windowSize: window,
      );
    });
  }

  /// End the resize: report the new size, then glide back to the docked corner.
  void _endResize() {
    final size = _dragCardSize;
    final topLeft = _dragTopLeft;
    final window = _overlaySize;
    _resizeStartSize = null;
    _resizeDelta = Offset.zero;
    if (size == null || topLeft == null || window == null) {
      _clearDrag();
      return;
    }
    widget.onResize(size);
    _snapFrom = topLeft;
    _snapTo = _cornerTopLeft(widget.corner, size, window);
    _snapCtrl.forward(from: 0);
  }
```

- [ ] **Step 5: Render size from fractions + pass corner/grip into the card**

In `build`, replace:

```dart
    final cardSize = Size(media.width * 0.3, media.height * 0.5);
```

with:

```dart
    final cardSize = _dragCardSize ??
        Size(
          media.width * (widget.widthFrac ?? 0.30),
          media.height * (widget.heightFrac ?? 0.50),
        );
```

> `_dragCardSize` is non-null only during an active drag/resize; at rest the
> fractions (or defaults) drive the size.

In `_buildCard`, pass the corner, reset callback, and resize handlers into
`_GlassCard` (add these args to the `_GlassCard(...)` call):

```dart
        corner: widget.corner,
        onResetSize: widget.onResetSize,
        onResizeStart: _startResize,
        onResizeUpdate: _updateResize,
        onResizeEnd: _endResize,
```

- [ ] **Step 6: Add the params to `_GlassCard` and render grip + reset**

In `_GlassCard`'s constructor add:

```dart
    required this.corner,
    required this.onResetSize,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
```

and fields:

```dart
  final ChatCorner corner;
  final VoidCallback onResetSize;
  final VoidCallback onResizeStart;
  final void Function(Offset delta) onResizeUpdate;
  final VoidCallback onResizeEnd;
```

Add the import to `chat_overlay.dart` if not already present:
`import 'chat_corner.dart';` (already imported — verify).

In the header `Row`, insert a reset button just before the existing collapse
`GestureDetector` (i.e. before the `Icons.chevron_right` block):

```dart
                      GestureDetector(
                        key: const ValueKey('chat-reset-size'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onResetSize,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Icon(Icons.crop_free,
                              size: 16, color: m.textDim),
                        ),
                      ),
```

Wrap the card's outer `DecoratedBox` return value in a `Stack` so the grip can
sit at the bottom-right. Change the `build` `return DecoratedBox(...)` to:

```dart
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          // ...existing DecoratedBox unchanged...
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            key: const ValueKey('chat-resize-grip'),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (_) => onResizeStart(),
            onPanUpdate: (d) => onResizeUpdate(d.delta),
            onPanEnd: (_) => onResizeEnd(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.open_in_full, size: 14, color: m.accent),
            ),
          ),
        ),
      ],
    );
```

> Keep the existing `DecoratedBox(...)` body verbatim as the first Stack child;
> only the outer wrapper changes. `DragStartBehavior` is already imported at the
> top of the file.

- [ ] **Step 7: Run the widget test**

Run: `$FLUTTER test test/ui/chat/chat_overlay_resize_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 8: Run analyze**

Run: `$FLUTTER analyze lib/ui/chat/chat_overlay.dart`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/ui/chat/chat_overlay.dart test/ui/chat/chat_overlay_resize_test.dart
git commit -m "feat: add resize grip and reset button to chat card"
```

---

## Task 4: Wire persistence through HomeScreen / app / main

**Files:**
- Modify: `lib/ui/home_screen.dart`
- Modify: `lib/app.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Accept settings + initial size in HomeScreen**

In `lib/ui/home_screen.dart`, find the `HomeScreen` constructor and add params.
Add the import near the top:

```dart
import '../core/data/settings_store.dart';
```

Add constructor params (alongside `history`):

```dart
    required this.settings,
    this.initialWidthFrac,
    this.initialHeightFrac,
```

Add fields:

```dart
  final SettingsStore settings;
  final double? initialWidthFrac;
  final double? initialHeightFrac;
```

- [ ] **Step 2: Seed the layout from the initial size**

Replace the field initializer at line ~88:

```dart
  ChatOverlayLayout _chatLayout = const ChatOverlayLayout();
```

with a `late` field seeded in `initState`. Change the declaration to:

```dart
  late ChatOverlayLayout _chatLayout;
```

and in `initState` (add if missing; otherwise add this line near the top of the
existing `initState`):

```dart
    _chatLayout = ChatOverlayLayout(
      widthFrac: widget.initialWidthFrac,
      heightFrac: widget.initialHeightFrac,
    );
```

- [ ] **Step 3: Pass size + persist callbacks to ChatOverlay**

In the `ChatOverlay(...)` call (around line 523), add:

```dart
                      widthFrac: _chatLayout.widthFrac,
                      heightFrac: _chatLayout.heightFrac,
                      onResize: (size) {
                        final media = MediaQuery.of(context).size;
                        setState(() =>
                            _chatLayout = _chatLayout.applyResize(size, media));
                        widget.settings.set(
                          kChatCardSizeSettingKey,
                          formatCardSizeFraction(
                            _chatLayout.widthFrac!,
                            _chatLayout.heightFrac!,
                          ),
                        );
                      },
                      onResetSize: () {
                        setState(() => _chatLayout = _chatLayout.resetSize());
                        widget.settings.set(kChatCardSizeSettingKey, '');
                      },
```

Add the import for the format helper if not already pulled in via the layout
import (it lives in `chat_overlay_layout.dart`, which HomeScreen already
imports — verify the import line exists; if HomeScreen imports the layout it has
access to `formatCardSizeFraction`).

- [ ] **Step 4: Thread settings + initial size through app.dart**

In `lib/app.dart`, add fields to `MeowWatchApp`:

```dart
  final double? initialCardWidthFrac;
  final double? initialCardHeightFrac;
```

Add them to the constructor:

```dart
    this.initialCardWidthFrac,
    this.initialCardHeightFrac,
```

In the `HomeScreen(...)` construction, add:

```dart
                settings: widget.settings,
                initialWidthFrac: widget.initialCardWidthFrac,
                initialHeightFrac: widget.initialCardHeightFrac,
```

- [ ] **Step 5: Load the setting at startup in main.dart**

In `lib/main.dart`, after the existing theme load line
(`final savedTheme = ...`), add:

```dart
  final (cardW, cardH) =
      parseCardSizeFraction(await settings.get(kChatCardSizeSettingKey));
```

Add the import at the top of `main.dart`:

```dart
import 'ui/chat/chat_overlay_layout.dart';
```

Then pass into `MeowWatchApp(...)`:

```dart
    initialCardWidthFrac: cardW,
    initialCardHeightFrac: cardH,
```

- [ ] **Step 6: Run analyze + full test suite**

Run: `$FLUTTER analyze`
Expected: `No issues found!`

Run: `$FLUTTER test`
Expected: all pass. If a golden test under `test/ui/chat/` fails because the
header gained the reset icon, regenerate it:

Run: `$FLUTTER test test/ui/chat/chat_overlay_golden_test.dart --update-goldens`
then open the PNG(s) under `test/ui/chat/goldens/` and confirm the reset icon
looks right before continuing.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/home_screen.dart lib/app.dart lib/main.dart test/ui/chat/goldens
git commit -m "feat: persist chat card size across launches"
```

---

## Task 5: Version bump + roadmap + manual test

**Files:**
- Modify: `lib/core/app_version.dart`, `pubspec.yaml`, `docs/ROADMAP.md`

- [ ] **Step 1: Bump versions**

In `lib/core/app_version.dart` change:

```dart
const String appVersion = '0.1.0-alpha';
```

to:

```dart
const String appVersion = '0.1.1-alpha';
```

In `pubspec.yaml` change `version: 0.1.0-alpha+1` to `version: 0.1.1-alpha+1`.

- [ ] **Step 2: Note the feature in the roadmap**

Add a bullet under the current/most-recent phase in `docs/ROADMAP.md`:
`- Resizable chat card (drag grip + reset, size persists locally).`

- [ ] **Step 3: Build the Release and manual-test (per CLAUDE.md)**

```powershell
Stop-Process -Name meowwatch -Force -ErrorAction SilentlyContinue
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat build windows
```

Launch `build/windows/x64/runner/Release/meowwatch.exe` and verify:
- Drag the bottom-right grip → card resizes, stays on screen, re-docks to its
  corner on release.
- Reset button → card returns to default size, stays in its corner.
- Quit and relaunch → the resized size is remembered.
- The card still drags between corners and collapses to the peek tab correctly.

- [ ] **Step 4: Commit**

```bash
git add lib/core/app_version.dart pubspec.yaml docs/ROADMAP.md
git commit -m "chore: bump to 0.1.1-alpha; note resizable chat card in roadmap"
```

---

## Task 6: Release (triggers R2 auto-update test)

- [ ] **Step 1: Push main**

```bash
git push
```

- [ ] **Step 2: Tag and push to trigger the build → R2 pipeline**

```bash
git tag v0.1.1-alpha
git push origin v0.1.1-alpha
```

- [ ] **Step 3: Verify the release landed on R2**

After the Build workflow's `Create Release` job is green:

```bash
curl -s https://pub-6002641cc8a44c128f0684981b511991.r2.dev/releases/latest.json
```

Expected: JSON with `"version": "0.1.1-alpha"` and a `windows-x64` asset URL.

- [ ] **Step 4: End-to-end update test**

With a still-installed **0.1.0-alpha** Release build (the one that has the
correct r2.dev URL), open it → it should detect 0.1.1-alpha, prompt, download,
and apply the update, relaunching at 0.1.1-alpha.

---

## Self-review notes

- Spec coverage: resize grip (Task 3), bounds (Task 1), reset size-only (Task 3
  + layout `resetSize` Task 2), persistence as fractions (Tasks 2 + 4), startup
  load (Task 4), version bump (Task 5) — all covered.
- `formatCardSizeFraction` / `parseCardSizeFraction` / `applyResize` /
  `resetSize` / `computeResize` names are used consistently across tasks.
- `HomeScreen` already receives `history`; adding `settings` follows the same
  prop-drilling pattern as the theme. Verify the exact constructor parameter
  ordering in the real file when editing — names, not positions, are what matter.
