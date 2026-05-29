# Phase 3 — Chat Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A draggable, corner-snapping, edge-collapsing glass chat card over the video with basic text chat (send/receive + timestamps) over the Syncplay chat channel.

**Architecture:** Approach A — pure logic split from view. Position/collapse rules are pure functions + an immutable layout state (unit-tested headless, like Phase 2's `decideFollow`). A `ChatStore` subscribes to the existing `SyncCore.chat` stream and holds an append-only message list. Dumb widgets render state. Cozy theme colors hardcoded.

**Tech Stack:** Flutter 3.44 (Dart 3.12, via Puro), `flutter_test`. No new packages.

**Flutter binary:** `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat` (not on PATH). Use this absolute path in every command.

**Conventions (match existing code):**
- Immutable data classes are `@immutable` with `==`/`hashCode` (see `lib/core/sync/peer_state.dart`).
- Cozy palette: warm dark `Color(0xFF1A1410)`, card fill `Color(0xCC1A1410)`, amber accent `Color(0xFFD4A574)`, cream text `Color(0xFFF5E6D3)`, dim text `Color(0x99F5E6D3)`, border `Color(0x55D4A574)`.
- Tests live under `test/` mirroring `lib/` paths.

---

## File Structure

**Create:**
- `lib/ui/chat/chat_corner.dart` — `ChatCorner` enum + `SnapResult` + pure `computeSnap(...)`.
- `lib/ui/chat/chat_overlay_layout.dart` — immutable `ChatOverlayLayout` state + transitions.
- `lib/core/chat/chat_store.dart` — message list, subscribes to `SyncCore.chat`, stamps arrival time.
- `lib/ui/chat/chat_bubble.dart` — one message row (mine right / friend left + timestamp).
- `lib/ui/chat/chat_input.dart` — text field + send button.
- `lib/ui/chat/peek_tab.dart` — 14px collapsed tab with pulse.
- `lib/ui/chat/chat_overlay.dart` — assembles card: header drag, list, input, collapse↔peek.

**Modify:**
- `lib/core/sync/peer_state.dart` — add `timestamp` to `ChatMessage` + `copyWith`.
- `lib/ui/home_screen.dart` — construct/dispose `ChatStore`, add `ChatOverlay` to the Stack, `Tab` key toggles collapse.

**Test:**
- `test/ui/chat/chat_corner_test.dart`
- `test/ui/chat/chat_overlay_layout_test.dart`
- `test/core/chat/chat_store_test.dart`
- `test/ui/chat/chat_bubble_test.dart`
- `test/ui/chat/chat_input_test.dart`
- `test/ui/chat/peek_tab_test.dart`
- `test/ui/chat/chat_overlay_test.dart`

---

### Task 1: Add `timestamp` to `ChatMessage`

**Files:**
- Modify: `lib/core/sync/peer_state.dart:81-87`
- Test: `test/core/sync/chat_message_test.dart` (Create)

- [ ] **Step 1: Write the failing test**

Create `test/core/sync/chat_message_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';

void main() {
  test('timestamp defaults to null and copyWith sets it', () {
    const m = ChatMessage(username: 'lin', text: 'hi');
    expect(m.timestamp, isNull);

    final t = DateTime(2026, 5, 28, 21, 43);
    final stamped = m.copyWith(timestamp: t);
    expect(stamped.timestamp, t);
    expect(stamped.username, 'lin');
    expect(stamped.text, 'hi');
  });

  test('equality includes timestamp', () {
    final t = DateTime(2026, 5, 28);
    expect(
      ChatMessage(username: 'a', text: 'x', timestamp: t),
      ChatMessage(username: 'a', text: 'x', timestamp: t),
    );
    expect(
      const ChatMessage(username: 'a', text: 'x'),
      isNot(ChatMessage(username: 'a', text: 'x', timestamp: t)),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/chat_message_test.dart`
Expected: FAIL — `copyWith` not defined / `timestamp` not a parameter.

- [ ] **Step 3: Implement**

Replace the `ChatMessage` class in `lib/core/sync/peer_state.dart` (lines 81-87) with:

```dart
@immutable
class ChatMessage {
  const ChatMessage({
    required this.username,
    required this.text,
    this.timestamp,
  });

  final String username;
  final String text;

  /// When the message arrived locally. The Syncplay protocol carries no
  /// timestamp, so the chat store stamps this on receipt; null until then.
  final DateTime? timestamp;

  ChatMessage copyWith({DateTime? timestamp}) => ChatMessage(
        username: username,
        text: text,
        timestamp: timestamp ?? this.timestamp,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.username == username &&
      other.text == text &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(username, text, timestamp);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/chat_message_test.dart`
Expected: PASS — All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/peer_state.dart test/core/sync/chat_message_test.dart
git commit -m "feat: add timestamp field to ChatMessage"
```

---

### Task 2: Corner snap math (`computeSnap`)

Pure function: given where the card was dropped, decide which corner it snaps to, or whether it collapses into the right-edge dock.

**Files:**
- Create: `lib/ui/chat/chat_corner.dart`
- Test: `test/ui/chat/chat_corner_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/chat/chat_corner_test.dart`:

```dart
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';

void main() {
  const window = Size(1000, 800);
  const card = Size(300, 200);

  SnapResult snap(Offset topLeft) => computeSnap(
        dropTopLeft: topLeft,
        cardSize: card,
        windowSize: window,
      );

  test('top-left region snaps to topLeft', () {
    final r = snap(const Offset(20, 20));
    expect(r.collapsed, isFalse);
    expect(r.corner, ChatCorner.topLeft);
  });

  test('bottom-left region snaps to bottomLeft', () {
    final r = snap(const Offset(20, 560));
    expect(r.corner, ChatCorner.bottomLeft);
  });

  test('top-left of a left-leaning card mid-screen still picks by center', () {
    // center at (170,120) -> left & top
    expect(snap(const Offset(20, 20)).corner, ChatCorner.topLeft);
  });

  test('right-edge drop collapses into the dock', () {
    // card right edge = 690+300 = 990, within 48px of window width 1000
    final r = snap(const Offset(690, 300));
    expect(r.collapsed, isTrue);
    expect(r.corner, isNull);
  });

  test('a left-side drop never collapses', () {
    expect(snap(const Offset(20, 300)).collapsed, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_corner_test.dart`
Expected: FAIL — `chat_corner.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/ui/chat/chat_corner.dart`:

```dart
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Which corner the chat card is anchored to.
enum ChatCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Outcome of dropping the card after a drag: either snap to a corner, or
/// collapse into the right-edge peek dock.
@immutable
class SnapResult {
  const SnapResult.corner(ChatCorner this.corner) : collapsed = false;
  const SnapResult.collapse()
      : corner = null,
        collapsed = true;

  final ChatCorner? corner;
  final bool collapsed;

  @override
  bool operator ==(Object other) =>
      other is SnapResult &&
      other.corner == corner &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(corner, collapsed);
}

/// Decide where the card lands when released at [dropTopLeft].
///
/// Rule: if the card's right edge reaches into the [edgeDockZone] strip along
/// the window's right edge, it collapses. Otherwise it snaps to whichever
/// corner the card's center is nearest (left/right by x, top/bottom by y).
SnapResult computeSnap({
  required Offset dropTopLeft,
  required Size cardSize,
  required Size windowSize,
  double edgeDockZone = 48,
}) {
  final cardRight = dropTopLeft.dx + cardSize.width;
  if (windowSize.width - cardRight <= edgeDockZone) {
    return const SnapResult.collapse();
  }
  final centerX = dropTopLeft.dx + cardSize.width / 2;
  final centerY = dropTopLeft.dy + cardSize.height / 2;
  final left = centerX < windowSize.width / 2;
  final top = centerY < windowSize.height / 2;
  if (top) {
    return SnapResult.corner(left ? ChatCorner.topLeft : ChatCorner.topRight);
  }
  return SnapResult.corner(
      left ? ChatCorner.bottomLeft : ChatCorner.bottomRight);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_corner_test.dart`
Expected: PASS — All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/ui/chat/chat_corner.dart test/ui/chat/chat_corner_test.dart
git commit -m "feat: add chat card corner-snap math"
```

---

### Task 3: Layout state transitions (`ChatOverlayLayout`)

Immutable state holding the current corner + collapsed flag, plus the corner to restore to when expanding.

**Files:**
- Create: `lib/ui/chat/chat_overlay_layout.dart`
- Test: `test/ui/chat/chat_overlay_layout_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/chat/chat_overlay_layout_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/chat_overlay_layout.dart';

void main() {
  test('defaults to bottomLeft, expanded', () {
    const l = ChatOverlayLayout();
    expect(l.corner, ChatCorner.bottomLeft);
    expect(l.collapsed, isFalse);
  });

  test('applySnap to a corner moves there and stays expanded', () {
    final l = const ChatOverlayLayout()
        .applySnap(const SnapResult.corner(ChatCorner.topRight));
    expect(l.corner, ChatCorner.topRight);
    expect(l.collapsed, isFalse);
  });

  test('applySnap collapse remembers the current corner', () {
    final l = const ChatOverlayLayout(corner: ChatCorner.topRight)
        .applySnap(const SnapResult.collapse());
    expect(l.collapsed, isTrue);
    expect(l.lastCorner, ChatCorner.topRight);
  });

  test('toggle collapses an expanded card, remembering corner', () {
    final l = const ChatOverlayLayout(corner: ChatCorner.bottomRight).toggle();
    expect(l.collapsed, isTrue);
    expect(l.lastCorner, ChatCorner.bottomRight);
  });

  test('toggle expands a collapsed card back to lastCorner', () {
    final collapsed = const ChatOverlayLayout(
      corner: ChatCorner.bottomLeft,
      collapsed: true,
      lastCorner: ChatCorner.topRight,
    );
    final l = collapsed.toggle();
    expect(l.collapsed, isFalse);
    expect(l.corner, ChatCorner.topRight);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_overlay_layout_test.dart`
Expected: FAIL — `chat_overlay_layout.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/ui/chat/chat_overlay_layout.dart`:

```dart
import 'package:flutter/foundation.dart';

import 'chat_corner.dart';

/// Immutable placement state for the chat card: which corner it sits in,
/// whether it is collapsed to the peek tab, and the corner to restore to.
@immutable
class ChatOverlayLayout {
  const ChatOverlayLayout({
    this.corner = ChatCorner.bottomLeft,
    this.collapsed = false,
    this.lastCorner = ChatCorner.bottomLeft,
  });

  final ChatCorner corner;
  final bool collapsed;
  final ChatCorner lastCorner;

  ChatOverlayLayout copyWith({
    ChatCorner? corner,
    bool? collapsed,
    ChatCorner? lastCorner,
  }) =>
      ChatOverlayLayout(
        corner: corner ?? this.corner,
        collapsed: collapsed ?? this.collapsed,
        lastCorner: lastCorner ?? this.lastCorner,
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

  @override
  bool operator ==(Object other) =>
      other is ChatOverlayLayout &&
      other.corner == corner &&
      other.collapsed == collapsed &&
      other.lastCorner == lastCorner;

  @override
  int get hashCode => Object.hash(corner, collapsed, lastCorner);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_overlay_layout_test.dart`
Expected: PASS — All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/ui/chat/chat_overlay_layout.dart test/ui/chat/chat_overlay_layout_test.dart
git commit -m "feat: add chat overlay layout state transitions"
```

---

### Task 4: `ChatStore` — message list off the sync channel

Holds an append-only list, subscribes to `SyncCore.chat`, stamps each message's arrival time (clock injected for tests), republishes the list.

**Files:**
- Create: `lib/core/chat/chat_store.dart`
- Test: `test/core/chat/chat_store_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/chat/chat_store_test.dart`. The fake subclasses `SyncCore`, no-ops the abstract methods, and exposes a helper that calls the `@protected emitChat`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/chat/chat_store.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_core.dart';

class FakeSync extends SyncCore {
  final List<String> sent = <String>[];

  void incoming(ChatMessage m) => emitChat(m);

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {}

  @override
  void notifyLocalChange({required bool doSeek}) {}

  @override
  void sendChat(String text) => sent.add(text);

  @override
  Future<void> disposeBackend() async {}
}

void main() {
  test('appends incoming messages in order', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));
    sync.incoming(const ChatMessage(username: 'me', text: 'yo'));

    expect(store.messages.map((m) => m.text), ['hi', 'yo']);
    await store.dispose();
    await sync.dispose();
  });

  test('stamps arrival time using the injected clock', () async {
    final sync = FakeSync();
    final fixed = DateTime(2026, 5, 28, 21, 43);
    final store = ChatStore(sync: sync, now: () => fixed);

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));

    expect(store.messages.single.timestamp, fixed);
    await store.dispose();
    await sync.dispose();
  });

  test('emits the updated list on its stream', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);
    final future = store.stream.first;

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));

    final list = await future;
    expect(list.single.text, 'hi');
    await store.dispose();
    await sync.dispose();
  });

  test('send delegates to sync.sendChat', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    store.send('hello');

    expect(sync.sent, ['hello']);
    await store.dispose();
    await sync.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/chat/chat_store_test.dart`
Expected: FAIL — `chat_store.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/core/chat/chat_store.dart`:

```dart
import 'dart:async';

import '../sync/peer_state.dart';
import '../sync/sync_core.dart';

/// Holds the room's chat history and feeds it to the UI. Subscribes to
/// [SyncCore.chat], stamps each message's local arrival time, and republishes
/// the whole (immutable) list. Sending delegates to the sync core; the server
/// echoes our own message back on the same channel, so it lands in the list
/// through the normal receive path — no optimistic local insert.
class ChatStore {
  ChatStore({required SyncCore sync, DateTime Function() now = DateTime.now})
      : _sync = sync,
        _now = now {
    _sub = _sync.chat.listen(_onChat);
  }

  final SyncCore _sync;
  final DateTime Function() _now;
  late final StreamSubscription<ChatMessage> _sub;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final StreamController<List<ChatMessage>> _controller =
      StreamController<List<ChatMessage>>.broadcast();

  /// Current history, oldest first. Unmodifiable snapshot.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Fires the full list every time a message arrives.
  Stream<List<ChatMessage>> get stream => _controller.stream;

  void _onChat(ChatMessage m) {
    _messages.add(m.timestamp == null ? m.copyWith(timestamp: _now()) : m);
    _controller.add(messages);
  }

  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _sync.sendChat(trimmed);
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _controller.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/chat/chat_store_test.dart`
Expected: PASS — All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/core/chat/chat_store.dart test/core/chat/chat_store_test.dart
git commit -m "feat: add ChatStore over the sync chat channel"
```

---

### Task 5: `ChatBubble` widget

One message row. Mine (username == my username) right-aligned amber; friend left-aligned dark. Dim `HH:MM` timestamp under the text.

**Files:**
- Create: `lib/ui/chat/chat_bubble.dart`
- Test: `test/ui/chat/chat_bubble_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/chat/chat_bubble_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/ui/chat/chat_bubble.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows text and HH:MM timestamp', (tester) async {
    await tester.pumpWidget(host(ChatBubble(
      message: ChatMessage(
        username: 'lin',
        text: 'hello there',
        timestamp: DateTime(2026, 5, 28, 9, 5),
      ),
      myUsername: 'me',
    )));

    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
  });

  testWidgets('mine aligns right, friend aligns left', (tester) async {
    await tester.pumpWidget(host(Column(children: [
      ChatBubble(
        message: const ChatMessage(username: 'me', text: 'mine'),
        myUsername: 'me',
      ),
      ChatBubble(
        message: const ChatMessage(username: 'lin', text: 'theirs'),
        myUsername: 'me',
      ),
    ])));

    final mine = tester.widget<Align>(find.ancestor(
      of: find.text('mine'),
      matching: find.byType(Align),
    ).first);
    final theirs = tester.widget<Align>(find.ancestor(
      of: find.text('theirs'),
      matching: find.byType(Align),
    ).first);

    expect(mine.alignment, Alignment.centerRight);
    expect(theirs.alignment, Alignment.centerLeft);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_bubble_test.dart`
Expected: FAIL — `chat_bubble.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/ui/chat/chat_bubble.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';

/// One chat message. Own messages sit right (amber); the friend's sit left
/// (dark). A dim HH:MM time shows under the text.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.myUsername,
  });

  final ChatMessage message;
  final String myUsername;

  bool get _mine => message.username == myUsername;

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ts = message.timestamp;
    return Align(
      alignment: _mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _mine ? const Color(0x33D4A574) : const Color(0x55241B14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x33D4A574)),
        ),
        child: Column(
          crossAxisAlignment:
              _mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: const TextStyle(color: Color(0xFFF5E6D3), fontSize: 14),
            ),
            if (ts != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _hhmm(ts),
                  style:
                      const TextStyle(color: Color(0x99F5E6D3), fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_bubble_test.dart`
Expected: PASS — All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/ui/chat/chat_bubble.dart test/ui/chat/chat_bubble_test.dart
git commit -m "feat: add ChatBubble widget"
```

---

### Task 6: `ChatInput` widget

Text field + send button. Submits on Enter and on the button. Clears after a non-empty send.

**Files:**
- Create: `lib/ui/chat/chat_input.dart`
- Test: `test/ui/chat/chat_input_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/chat/chat_input_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_input.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('send button fires onSend with text and clears field',
      (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(host(ChatInput(onSend: sent.add)));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, ['hello']);
    expect(find.text('hello'), findsNothing); // field cleared
  });

  testWidgets('blank input does not fire onSend', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(host(ChatInput(onSend: sent.add)));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_input_test.dart`
Expected: FAIL — `chat_input.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/ui/chat/chat_input.dart`:

```dart
import 'package:flutter/material.dart';

/// Message composer: a text field plus a send button. Fires [onSend] with the
/// trimmed text (never blank) and clears itself.
class ChatInput extends StatefulWidget {
  const ChatInput({super.key, required this.onSend});

  final void Function(String text) onSend;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(color: Color(0xFFF5E6D3), fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Message…',
                hintStyle: TextStyle(color: Color(0x66F5E6D3)),
                isDense: true,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0x55D4A574)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0x55D4A574)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFD4A574)),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Color(0xFFD4A574)),
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_input_test.dart`
Expected: PASS — All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/ui/chat/chat_input.dart test/ui/chat/chat_input_test.dart
git commit -m "feat: add ChatInput widget"
```

---

### Task 7: `PeekTab` widget

The collapsed state: a narrow 14px-wide tab at the right edge. Tap expands. `pulsing` flag drives a highlight (set true briefly when a message arrives while collapsed — wiring lands in Task 9).

**Files:**
- Create: `lib/ui/chat/peek_tab.dart`
- Test: `test/ui/chat/peek_tab_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/chat/peek_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/peek_tab.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('is 14px wide and taps to expand', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(PeekTab(
      pulsing: false,
      onTap: () => tapped = true,
    )));

    final box = tester.getSize(find.byType(PeekTab));
    expect(box.width, 14);

    await tester.tap(find.byType(PeekTab));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/peek_tab_test.dart`
Expected: FAIL — `peek_tab.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/ui/chat/peek_tab.dart`:

```dart
import 'package:flutter/material.dart';

/// The collapsed chat: a 14px tab hugging the right edge. Tap to expand.
/// [pulsing] brightens it to hint at a freshly arrived message.
class PeekTab extends StatelessWidget {
  const PeekTab({super.key, required this.pulsing, required this.onTap});

  final bool pulsing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 14,
        height: 64,
        decoration: BoxDecoration(
          color: pulsing ? const Color(0xFFD4A574) : const Color(0xCC1A1410),
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
          border: Border.all(color: const Color(0x55D4A574)),
        ),
        child: const Center(
          child: Icon(Icons.chat_bubble_outline,
              size: 10, color: Color(0xFFF5E6D3)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/peek_tab_test.dart`
Expected: PASS — All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/ui/chat/peek_tab.dart test/ui/chat/peek_tab_test.dart
git commit -m "feat: add PeekTab collapsed widget"
```

---

### Task 8: `ChatOverlay` — assemble the card

Glass card holding a draggable header, the message list, and the input. Owns a `ChatOverlayLayout` in state. Dragging the header moves a free-floating position; on release `computeSnap` decides the corner or collapse. Collapsed → renders `PeekTab`. Positioning maps the corner to a `Positioned` within the parent `Stack`.

**Files:**
- Create: `lib/ui/chat/chat_overlay.dart`
- Test: `test/ui/chat/chat_overlay_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/chat/chat_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/ui/chat/chat_input.dart';
import 'package:meowwatch/ui/chat/chat_overlay.dart';
import 'package:meowwatch/ui/chat/peek_tab.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Stack(children: [child]),
        ),
      );

  testWidgets('renders messages and an input when expanded', (tester) async {
    await tester.pumpWidget(host(ChatOverlay(
      messages: const [
        ChatMessage(username: 'lin', text: 'hi'),
        ChatMessage(username: 'me', text: 'yo'),
      ],
      myUsername: 'me',
      collapsed: false,
      onSend: (_) {},
      onToggleCollapsed: () {},
      onSnap: (_) {},
    )));

    expect(find.text('hi'), findsOneWidget);
    expect(find.text('yo'), findsOneWidget);
    expect(find.byType(ChatInput), findsOneWidget);
    expect(find.byType(PeekTab), findsNothing);
  });

  testWidgets('renders only the peek tab when collapsed', (tester) async {
    await tester.pumpWidget(host(ChatOverlay(
      messages: const [ChatMessage(username: 'lin', text: 'hi')],
      myUsername: 'me',
      collapsed: true,
      onSend: (_) {},
      onToggleCollapsed: () {},
      onSnap: (_) {},
    )));

    expect(find.byType(PeekTab), findsOneWidget);
    expect(find.byType(ChatInput), findsNothing);
    expect(find.text('hi'), findsNothing);
  });

  testWidgets('tapping the peek tab requests expand', (tester) async {
    var toggled = false;
    await tester.pumpWidget(host(ChatOverlay(
      messages: const [],
      myUsername: 'me',
      collapsed: true,
      onSend: (_) {},
      onToggleCollapsed: () => toggled = true,
      onSnap: (_) {},
    )));

    await tester.tap(find.byType(PeekTab));
    await tester.pump();
    expect(toggled, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_overlay_test.dart`
Expected: FAIL — `chat_overlay.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/ui/chat/chat_overlay.dart`. This is a presentational widget: parent owns layout/collapsed state and passes callbacks. The widget positions itself by corner, renders the glass card or the peek tab, and reports drag-release via `onSnap` (using `computeSnap`). It reads the parent `Stack`'s size from `LayoutBuilder` is not available inside a `Stack` child cleanly, so the card uses a fixed fractional size via `FractionallySizedBox` wrapped in a `Positioned.fill` + `Align`, and drag uses the global drag delta against `MediaQuery` size.

```dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../../core/sync/peer_state.dart';
import 'chat_bubble.dart';
import 'chat_corner.dart';
import 'chat_input.dart';
import 'peek_tab.dart';

/// The floating chat card. Presentational: the parent owns the layout state
/// (corner + collapsed) and supplies callbacks. Dragging the header reports a
/// drag-release decision through [onSnap]; collapse/expand goes through
/// [onToggleCollapsed].
class ChatOverlay extends StatefulWidget {
  const ChatOverlay({
    super.key,
    required this.messages,
    required this.myUsername,
    required this.collapsed,
    required this.onSend,
    required this.onToggleCollapsed,
    required this.onSnap,
    this.corner = ChatCorner.bottomLeft,
    this.pulsing = false,
  });

  final List<ChatMessage> messages;
  final String myUsername;
  final bool collapsed;
  final ChatCorner corner;
  final bool pulsing;
  final void Function(String text) onSend;
  final VoidCallback onToggleCollapsed;
  final void Function(SnapResult result) onSnap;

  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  // While dragging, a free top-left offset overrides corner placement.
  Offset? _dragTopLeft;

  Alignment _alignmentFor(ChatCorner c) {
    switch (c) {
      case ChatCorner.topLeft:
        return Alignment.topLeft;
      case ChatCorner.topRight:
        return Alignment.topRight;
      case ChatCorner.bottomLeft:
        return Alignment.bottomLeft;
      case ChatCorner.bottomRight:
        return Alignment.bottomRight;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) {
      return Align(
        alignment: Alignment.centerRight,
        child: PeekTab(pulsing: widget.pulsing, onTap: widget.onToggleCollapsed),
      );
    }

    final media = MediaQuery.of(context).size;
    final cardSize = Size(media.width * 0.3, media.height * 0.5);

    final card = _GlassCard(
      width: cardSize.width,
      maxHeight: cardSize.height,
      onHeaderDragUpdate: (delta) {
        setState(() {
          final base = _dragTopLeft ?? _cornerTopLeft(widget.corner, media, cardSize);
          _dragTopLeft = base + delta;
        });
      },
      onHeaderDragEnd: () {
        final topLeft = _dragTopLeft;
        if (topLeft != null) {
          widget.onSnap(computeSnap(
            dropTopLeft: topLeft,
            cardSize: cardSize,
            windowSize: media,
          ));
        }
        setState(() => _dragTopLeft = null);
      },
      onCollapse: widget.onToggleCollapsed,
      messages: widget.messages,
      myUsername: widget.myUsername,
      onSend: widget.onSend,
    );

    final topLeft = _dragTopLeft;
    if (topLeft != null) {
      return Positioned(left: topLeft.dx, top: topLeft.dy, child: card);
    }
    return Align(alignment: _alignmentFor(widget.corner), child: Padding(
      padding: const EdgeInsets.all(12),
      child: card,
    ));
  }

  Offset _cornerTopLeft(ChatCorner c, Size window, Size card) {
    const m = 12.0;
    final left = (c == ChatCorner.topLeft || c == ChatCorner.bottomLeft)
        ? m
        : window.width - card.width - m;
    final top = (c == ChatCorner.topLeft || c == ChatCorner.topRight)
        ? m
        : window.height - card.height - m;
    return Offset(left, top);
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.width,
    required this.maxHeight,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
    required this.onCollapse,
    required this.messages,
    required this.myUsername,
    required this.onSend,
  });

  final double width;
  final double maxHeight;
  final void Function(Offset delta) onHeaderDragUpdate;
  final VoidCallback onHeaderDragEnd;
  final VoidCallback onCollapse;
  final List<ChatMessage> messages;
  final String myUsername;
  final void Function(String text) onSend;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: const Color(0xCC1A1410),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x55D4A574)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => onHeaderDragUpdate(d.delta),
                onPanEnd: (_) => onHeaderDragEnd(),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator,
                          size: 16, color: Color(0x99F5E6D3)),
                      const Spacer(),
                      const Text('Chat',
                          style: TextStyle(
                              color: Color(0xFFF5E6D3), fontSize: 13)),
                      const Spacer(),
                      GestureDetector(
                        onTap: onCollapse,
                        child: const Icon(Icons.chevron_right,
                            size: 18, color: Color(0xFFD4A574)),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final m in messages)
                      ChatBubble(message: m, myUsername: myUsername),
                  ],
                ),
              ),
              ChatInput(onSend: onSend),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_overlay_test.dart`
Expected: PASS — All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/ui/chat/chat_overlay.dart test/ui/chat/chat_overlay_test.dart
git commit -m "feat: assemble ChatOverlay card with drag/snap/collapse"
```

---

### Task 9: Wire chat into `HomeScreen`

Construct the `ChatStore`, track the connected username, drive a `ChatOverlayLayout` in state, render `ChatOverlay` in the video Stack, and bind `Tab` to toggle collapse. Pulse the peek tab when a message arrives while collapsed (peek for 2s — implemented by setting `pulsing` true then false on a timer).

**Files:**
- Modify: `lib/ui/home_screen.dart`
- Test: manual (covered in Task 10); widget-level behavior is already unit-tested in Tasks 2–8.

- [ ] **Step 1: Add fields and ChatStore construction**

In `_HomeScreenState`, add imports at the top of `lib/ui/home_screen.dart`:

```dart
import '../core/chat/chat_store.dart';
import 'chat/chat_corner.dart';
import 'chat/chat_overlay.dart';
import 'chat/chat_overlay_layout.dart';
```

Add fields alongside the existing ones (after `_presenceSub`):

```dart
  late final ChatStore _chat;
  ChatOverlayLayout _chatLayout = const ChatOverlayLayout();
  List<ChatMessage> _messages = const <ChatMessage>[];
  String _username = '';
  bool _peekPulsing = false;
  Timer? _peekTimer;
  StreamSubscription<List<ChatMessage>>? _chatSub;
```

`ChatMessage` is already imported transitively via `peer_state.dart` (imported as `peer_state.dart`); add an explicit import if the analyzer complains:

```dart
import '../core/sync/peer_state.dart';
```

(It is already imported — confirm before adding a duplicate.)

- [ ] **Step 2: Initialize ChatStore in initState**

In `initState`, after `_bridge = ...start();`, add:

```dart
    _chat = ChatStore(sync: _sync);
    _chatSub = _chat.stream.listen((msgs) {
      if (!mounted) return;
      setState(() => _messages = msgs);
      if (_chatLayout.collapsed) _pulsePeek();
    });
```

- [ ] **Step 3: Add the pulse helper and capture username on connect**

Add this method to `_HomeScreenState`:

```dart
  void _pulsePeek() {
    setState(() => _peekPulsing = true);
    _peekTimer?.cancel();
    _peekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _peekPulsing = false);
    });
  }
```

In `_connect(...)`, record the username before calling `_sync.connect`:

```dart
  void _connect({
    required String server,
    required int port,
    required String username,
    required String room,
  }) {
    _username = username;
    unawaited(_sync.connect(
      server: server,
      port: port,
      username: username,
      room: room,
    ));
  }
```

- [ ] **Step 4: Dispose the new resources**

In `dispose()`, before `super.dispose()`, add:

```dart
    _peekTimer?.cancel();
    unawaited(_chatSub?.cancel());
    unawaited(_chat.dispose());
```

- [ ] **Step 5: Render ChatOverlay + bind Tab**

Wrap the video `Expanded` in a `Focus` that handles the `Tab` key, and add `ChatOverlay` to the inner `Stack`. Replace the `Stack` children block (the `fit: StackFit.expand` Stack that currently holds `VideoSurface` + hint banner) so it also includes the overlay:

```dart
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoSurface(core: _core),
                      if (hint != null)
                        Align(
                          alignment: const Alignment(0, -0.8),
                          child: _SyncHintBanner(text: hint),
                        ),
                      ChatOverlay(
                        messages: _messages,
                        myUsername: _username,
                        collapsed: _chatLayout.collapsed,
                        corner: _chatLayout.corner,
                        pulsing: _peekPulsing,
                        onSend: _chat.send,
                        onToggleCollapsed: () => setState(
                            () => _chatLayout = _chatLayout.toggle()),
                        onSnap: (result) => setState(
                            () => _chatLayout = _chatLayout.applySnap(result)),
                      ),
                    ],
                  );
```

Bind `Tab` to toggle: wrap the `VideoDropTarget` (the child of `Expanded`) in a `Focus`. Change the `Expanded(child: VideoDropTarget(...))` to:

```dart
          Expanded(
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.tab) {
                  setState(() => _chatLayout = _chatLayout.toggle());
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: VideoDropTarget(
                onFileDropped: _handleDropped,
                child: StreamBuilder<PlaybackState>(
                  // ...unchanged...
                ),
              ),
            ),
          ),
```

Add the services import for `LogicalKeyboardKey` / `KeyDownEvent` at the top:

```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 6: Verify the app analyzes and builds**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: No issues found!

Run the full test suite to confirm nothing regressed:

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test`
Expected: All tests passed!

- [ ] **Step 7: Commit**

```bash
git add lib/ui/home_screen.dart
git commit -m "feat: wire chat overlay into HomeScreen with Tab toggle"
```

---

### Task 10: Manual two-instance E2E + tag

**Files:** none (verification only).

- [ ] **Step 1: Build the Windows app**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat build windows`
Expected: build succeeds; exe at `build/windows/x64/runner/Release/meowwatch.exe`.

- [ ] **Step 2: Run two instances and exercise the checklist**

Launch the exe twice. In each, connect to the same room (use the dev connect bar), load the same video. Verify:
- Type in instance A → message appears in both A (right side) and B (left side), with an `HH:MM` timestamp.
- Type in B → appears in both, sides flipped.
- Drag the card header → release near each corner → it snaps there.
- Drag the card to the right edge → it collapses to the 14px peek tab.
- Click the peek tab → it expands to the last corner.
- Press `Tab` → toggles collapse/expand.
- With the card collapsed, send a message from the other instance → the peek tab pulses (brightens) for ~2s.

- [ ] **Step 3: Tag the phase**

```bash
git tag phase-3-complete
git log --oneline -1
```

- [ ] **Step 4: Update roadmap + memory**

Edit `docs/ROADMAP.md`: change the Phase 3 row status to `3 ✅` with "**Shipped (tag `phase-3-complete`).**" plus a one-line summary, and link this plan. Then:

```bash
git add docs/ROADMAP.md
git commit -m "docs: mark Phase 3 shipped"
```

---

## Notes for the implementer

- **No new packages.** Everything uses `flutter`/`flutter_test` already in `pubspec.yaml`.
- **`Tab` key caveat:** `Tab` is also Flutter's default focus-traversal key. The `Focus.onKeyEvent` handler returns `KeyEventResult.handled` for `Tab`, which stops traversal — that is intended here. If focus-stealing misbehaves during manual testing, note it for follow-up; it does not block the phase.
- **Custom-event sentinel (`__meow__:`)** is out of scope (Phase 6). Do not filter or special-case it now.
- **Presence-in-chat notices** are out of scope (Phase 6). The existing `_SyncHintBanner` and `_peers` presence logic stay as-is.
