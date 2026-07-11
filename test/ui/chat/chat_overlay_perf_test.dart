import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_bubble.dart';
import 'package:meowwatch/ui/chat/chat_overlay.dart';

// Performance guards for the chat card (the P1/P2 findings of the 2026-07 perf
// review): the message list must build lazily, dragging the card must not
// rebuild its contents, and a history trimmed by the ChatStore cap must still
// surface newly appended messages.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: themeDataFor(MeowThemeId.cozy),
    home: Scaffold(body: Stack(children: [child])),
  );

  List<ChatMessage> manyMessages(int n) => [
    for (var i = 0; i < n; i++)
      ChatMessage(username: 'lin', text: 'msg-$i', isMine: false),
  ];

  testWidgets('message list builds lazily via a builder delegate', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ChatOverlay(
          messages: manyMessages(5),
          collapsed: false,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        ),
      ),
    );

    // A children:[...] list constructs every message widget on every rebuild;
    // a builder delegate only constructs what scrolls into view.
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
  });

  testWidgets('dragging the header does not rebuild the message bubbles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      host(
        ChatOverlay(
          messages: manyMessages(3),
          collapsed: false,
          onSend: (_) {},
          onToggleCollapsed: () {},
          onSnap: (_) {},
        ),
      ),
    );
    await tester.pump();

    final handle = find.byIcon(Icons.drag_indicator);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();

    // Mid-drag baseline: the card has switched into its free-floating render
    // path and built its contents once.
    final before = tester
        .widgetList<ChatBubble>(find.byType(ChatBubble))
        .toList();
    expect(before, isNotEmpty);

    // Further pointer moves must reposition the card without rebuilding its
    // contents — every bubble stays the same widget instance.
    await gesture.moveBy(const Offset(15, 10));
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 5));
    await tester.pump();

    final after = tester
        .widgetList<ChatBubble>(find.byType(ChatBubble))
        .toList();
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(
        identical(before[i], after[i]),
        isTrue,
        reason: 'bubble $i was rebuilt by a pointer move during drag',
      );
    }

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('appended messages are still detected when the history was '
      'trimmed to a same-length list', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var messages = manyMessages(40);
    final base = messages;
    late StateSetter setOuter;

    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return ChatOverlay(
              messages: messages,
              collapsed: false,
              onSend: (_) {},
              onToggleCollapsed: () {},
              onSnap: (_) {},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The ChatStore cap trims the oldest line as a new one arrives, so the
    // list keeps its length while sharing all surviving instances. The first
    // build doesn't auto-scroll, so the genuinely new message must surface as
    // the unread badge — a length check alone would miss it.
    setOuter(() {
      messages = [
        ...base.skip(1),
        const ChatMessage(username: 'lin', text: 'fresh'),
      ];
    });
    await tester.pumpAndSettle();

    expect(find.text('↓ 1 new message'), findsOneWidget);
  });

  testWidgets('the New Messages divider stays above its message across a '
      'later trim', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var messages = manyMessages(40);
    late StateSetter setOuter;

    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return ChatOverlay(
              messages: messages,
              collapsed: false,
              onSend: (_) {},
              onToggleCollapsed: () {},
              onSnap: (_) {},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trim + append pins the divider above the first unread message.
    final base = messages;
    setOuter(() {
      messages = [
        ...base.skip(1),
        const ChatMessage(username: 'lin', text: 'fresh'),
      ];
    });
    await tester.pumpAndSettle();

    // Bring the unread boundary into view.
    await tester.tap(find.text('↓ 1 new message'));
    await tester.pumpAndSettle();
    expect(find.text('New Messages'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('New Messages')).dy,
      lessThan(tester.getTopLeft(find.text('fresh')).dy),
    );

    // Another trimmed update while the divider is showing — my own echoed
    // message, so no new unread run starts and the divider is not re-pinned.
    // It must move with its message, not sit at a stale absolute index (which
    // would put it below 'fresh', above the newest line).
    final current = messages;
    setOuter(() {
      messages = [
        ...current.skip(1),
        const ChatMessage(username: 'me', text: 'mine', isMine: true),
      ];
    });
    await tester.pumpAndSettle();

    expect(find.text('New Messages'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('New Messages')).dy,
      lessThan(tester.getTopLeft(find.text('fresh')).dy),
    );

    // Let the divider's post-read linger timer elapse so no timer is pending
    // at teardown.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('unread badge and divider re-pin when the oldest unread lines '
      'age out under the retention cap', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var messages = manyMessages(40);
    late StateSetter setOuter;

    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return ChatOverlay(
              messages: messages,
              collapsed: false,
              onSend: (_) {},
              onToggleCollapsed: () {},
              onSnap: (_) {},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scrolled up (first build doesn't auto-scroll). Three peer lines arrive
    // and pile up unread, pinning the divider above the first of them.
    final base = messages;
    setOuter(() {
      messages = [
        ...base,
        const ChatMessage(username: 'lin', text: 'u1'),
        const ChatMessage(username: 'lin', text: 'u2'),
        const ChatMessage(username: 'lin', text: 'u3'),
      ];
    });
    await tester.pumpAndSettle();
    expect(find.text('↓ 3 new messages'), findsOneWidget);

    // Now the retention cap bites hard: the whole read backlog *and* the two
    // oldest unread lines age out, leaving only the third unread line, while a
    // fourth unread line arrives in the same snapshot. The badge must report
    // the two lines still retained (not keep the two trimmed ones in its
    // count), and the "New Messages" divider must re-pin to the oldest unread
    // line still present instead of vanishing.
    final grown = messages; // [...40 read, u1, u2, u3]
    setOuter(() {
      messages = [
        grown[42], // u3 — the only surviving earlier unread line
        const ChatMessage(username: 'lin', text: 'u4'),
      ];
    });
    await tester.pumpAndSettle();

    expect(find.text('↓ 2 new messages'), findsOneWidget);
    expect(find.text('↓ 4 new messages'), findsNothing);
    expect(find.text('New Messages'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('New Messages')).dy,
      lessThan(tester.getTopLeft(find.text('u3')).dy),
    );
  });
}
