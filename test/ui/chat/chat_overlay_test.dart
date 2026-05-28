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
