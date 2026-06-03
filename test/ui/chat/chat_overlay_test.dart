import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_input.dart';
import 'package:meowwatch/ui/chat/chat_overlay.dart';
import 'package:meowwatch/ui/chat/peek_tab.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
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

  testWidgets('dragging the header moves the card by the drag delta '
      '(no first-grab teleport)', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

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
    await tester.pump();

    // The drag handle anchors the header; grabbing it should move the card
    // rigidly, not jump it to a recomputed corner on the first update.
    final handle = find.byIcon(Icons.drag_indicator);
    final before = tester.getTopLeft(handle);

    const move = Offset(40, -30);
    // The move icon now sits at the header's left:24 inset, clear of the 22x22
    // top-left resize grip, so its center lands on the move arena directly. (It
    // used to overlap the grip and needed a +10px nudge to bypass it.)
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(move);
    await tester.pump();
    final after = tester.getTopLeft(handle);

    expect((after - before).dx, closeTo(move.dx, 1.0));
    expect((after - before).dy, closeTo(move.dy, 1.0));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('shows the five dock hints only while dragging', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(host(ChatOverlay(
      messages: const [ChatMessage(username: 'lin', text: 'hi')],
      myUsername: 'me',
      collapsed: false,
      onSend: (_) {},
      onToggleCollapsed: () {},
      onSnap: (_) {},
    )));
    await tester.pump();

    // No hints at rest.
    expect(find.byIcon(Icons.north_west), findsNothing);
    expect(find.byIcon(Icons.south_east), findsNothing);

    final handle = find.byIcon(Icons.drag_indicator);
    // The move icon's left:24 inset keeps its center clear of the top-left
    // resize grip (see the move test above); a grip hit would start a resize,
    // which suppresses the dock hints.
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(40, -30));
    await tester.pump();

    // All four corner targets are present mid-drag.
    expect(find.byIcon(Icons.north_west), findsOneWidget);
    expect(find.byIcon(Icons.north_east), findsOneWidget);
    expect(find.byIcon(Icons.south_west), findsOneWidget);
    expect(find.byIcon(Icons.south_east), findsOneWidget);

    await gesture.up();
    await tester.pump();

    // Hints clear on release.
    expect(find.byIcon(Icons.north_west), findsNothing);
  });

  testWidgets('opening the card focuses the message box', (tester) async {
    Widget overlay(bool collapsed) => host(ChatOverlay(
          messages: const [],
          myUsername: 'me',
          collapsed: collapsed,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        ));

    // Start collapsed (peek tab) — no text field, nothing focused.
    await tester.pumpWidget(overlay(true));
    await tester.pump();

    // Expand (peek → card): the message box should grab focus on its own.
    await tester.pumpWidget(overlay(false));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  // A list tall enough to overflow the card, so the newest message starts
  // off-screen and "scrolled into view" is a meaningful assertion. Off-viewport
  // list children are not matched by find.text, so finding the last message
  // proves the list scrolled down to it.
  List<ChatMessage> manyMessages(int n) => [
        for (var i = 0; i < n; i++) ChatMessage(username: 'lin', text: 'msg-$i'),
      ];

  testWidgets('a new message scrolls into view if already at bottom',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    Widget overlay(List<ChatMessage> messages) => host(ChatOverlay(
          messages: messages,
          myUsername: 'me',
          collapsed: false,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        ));

    await tester.pumpWidget(overlay(manyMessages(40)));
    await tester.pumpAndSettle();
    // Scroll to the bottom
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // A fresh message arrives while open — the list scrolls to show it.
    await tester.pumpWidget(overlay(manyMessages(41)));
    await tester.pumpAndSettle();
    expect(find.text('msg-40'), findsOneWidget);
  });

  testWidgets('a new message shows unread badge if scrolled up',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    Widget overlay(List<ChatMessage> messages) => host(ChatOverlay(
          messages: messages,
          myUsername: 'me',
          collapsed: false,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        ));

    await tester.pumpWidget(overlay(manyMessages(40)));
    await tester.pumpAndSettle();
    // No auto-scroll on first build: the bottom message is still off-screen.
    expect(find.text('msg-39'), findsNothing);

    // A fresh message arrives while open — it does NOT scroll, but shows badge.
    await tester.pumpWidget(overlay(manyMessages(41)));
    await tester.pumpAndSettle();
    expect(find.text('msg-40'), findsNothing);
    expect(find.text('↓ 1 new message'), findsOneWidget);

    // Tapping the badge scrolls to bottom and clears the badge
    await tester.tap(find.text('↓ 1 new message'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4)); // wait for divider timer
    await tester.pumpAndSettle();
    expect(find.text('msg-40'), findsOneWidget);
    expect(find.text('↓ 1 new message'), findsNothing);
  });

  testWidgets('unread transition notifies the parent without a build-phase '
      'crash (#43)', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var count = 40;
    final unreadEvents = <bool>[];
    late StateSetter setOuter;

    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return ChatOverlay(
          messages: manyMessages(count),
          myUsername: 'me',
          collapsed: false,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
          // Mirror HomeScreen: the callback drives a parent setState. The new
          // message arrives via didUpdateWidget (the parent's build phase), so
          // firing this synchronously would throw "setState() called during
          // build" — it must be deferred past the frame.
          onUnreadChanged: (has) {
            unreadEvents.add(has);
            setOuter(() {});
          },
        );
      },
    )));
    await tester.pumpAndSettle();
    // First build doesn't auto-scroll, so the card is scrolled up: a new
    // message bumps unread rather than scrolling into view.
    expect(unreadEvents, isEmpty);

    setOuter(() => count = 41);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(unreadEvents, contains(true));
  });

  testWidgets('reopening the card scrolls the latest message into view even '
      'though messages piled up while it was collapsed', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    Widget overlay({required bool collapsed, required int count}) =>
        host(ChatOverlay(
          messages: manyMessages(count),
          myUsername: 'me',
          collapsed: collapsed,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        ));

    // Collapsed with a backlog: the list is unmounted, so no scroll runs.
    await tester.pumpWidget(overlay(collapsed: true, count: 40));
    await tester.pump();

    // Reopen — the list mounts and should land at the newest message.
    await tester.pumpWidget(overlay(collapsed: false, count: 40));
    await tester.pumpAndSettle();
    expect(find.text('msg-39'), findsOneWidget);

    // Pinned hard to the bottom: offset sits exactly at maxScrollExtent, not a
    // stale near-bottom position left by a single frame-racing jump.
    final list = tester.widget<ListView>(find.byType(ListView));
    final controller = list.controller!;
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('a "New Messages" divider survives reopen and auto-clears after '
      'the linger window (#32)', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    Widget overlay({required bool collapsed, required int count}) =>
        host(ChatOverlay(
          messages: manyMessages(count),
          myUsername: 'me',
          collapsed: collapsed,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        ));

    // Open with a backlog, then collapse: a message that lands while collapsed
    // marks the unread boundary (divider just above the first unread one).
    await tester.pumpWidget(overlay(collapsed: false, count: 40));
    await tester.pumpAndSettle();
    await tester.pumpWidget(overlay(collapsed: true, count: 40));
    await tester.pump();
    await tester.pumpWidget(overlay(collapsed: true, count: 41));
    await tester.pump();

    // Reopen. The card auto-scrolls to the bottom AND auto-focuses the input —
    // that programmatic focus must NOT wipe the divider (the regression this
    // pins): the user reopened precisely to see where they left off.
    await tester.pumpWidget(overlay(collapsed: false, count: 41));
    await tester.pumpAndSettle();
    expect(find.text('New Messages'), findsOneWidget);

    // Reopen scrolled to the bottom, so the unread linger timer is running.
    // Once it elapses the divider clears itself.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('New Messages'), findsNothing);
  });

  testWidgets('typing indicator toggling does not resize the message list',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    Widget overlay(String? typingLabel) => host(ChatOverlay(
          messages: manyMessages(40),
          myUsername: 'me',
          collapsed: false,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
          typingLabel: typingLabel,
        ));

    // Nobody typing: measure the list viewport height.
    await tester.pumpWidget(overlay(null));
    await tester.pumpAndSettle();
    final heightIdle = tester.getSize(find.byType(ListView)).height;

    // A peer starts typing — the reserved strip means the list keeps its height
    // (no shrink that would yank the newest bubble out of view).
    await tester.pumpWidget(overlay('lin is typing…'));
    await tester.pumpAndSettle();
    final heightTyping = tester.getSize(find.byType(ListView)).height;

    expect(heightTyping, heightIdle);
  });

  testWidgets('incoming messages increment unread when isUiIdle is true even if at bottom, and clear on wake', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var isUiIdle = true;
    var messageCount = 40;
    late StateSetter setOuter;

    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return ChatOverlay(
          messages: manyMessages(messageCount),
          myUsername: 'me',
          collapsed: false,
          isUiIdle: isUiIdle,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        );
      },
    )));
    await tester.pumpAndSettle();

    // Scroll to bottom
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // While idle, an incoming message should NOT clear the unread count, 
    // even though we are at the bottom.
    setOuter(() => messageCount = 41);
    await tester.pumpAndSettle();

    expect(find.text('↓ 1 new message'), findsOneWidget);

    // Wake the UI
    setOuter(() => isUiIdle = false);
    await tester.pumpAndSettle();

    // Since we are at the bottom, waking the UI should clear the unread count
    expect(find.text('↓ 1 new message'), findsNothing);
  });

  testWidgets('system messages do not increment unread or show badge', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var messages = manyMessages(40);
    late StateSetter setOuter;

    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return ChatOverlay(
          messages: messages,
          myUsername: 'me',
          collapsed: false,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        );
      },
    )));
    await tester.pumpAndSettle();
    
    // First build doesn't auto-scroll, so we are not at bottom.
    // Adding a system message should NOT trigger a new message badge.
    setOuter(() {
      messages = [
        ...messages,
        const ChatMessage(username: 'system', text: 'lin paused', system: true),
      ];
    });
    await tester.pumpAndSettle();

    expect(find.text('↓ 1 new message'), findsNothing);
  });
}
