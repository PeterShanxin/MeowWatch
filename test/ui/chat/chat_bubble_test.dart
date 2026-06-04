import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_bubble.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: child),
      );

  testWidgets('shows text and HH:MM timestamp', (tester) async {
    await tester.pumpWidget(host(ChatBubble(
      message: ChatMessage(
        username: 'lin',
        text: 'hello there',
        timestamp: DateTime(2026, 5, 28, 9, 5),
        isMine: false,
      ),
    )));

    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
  });

  testWidgets('friend bubble shows sender name, mine does not', (tester) async {
    await tester.pumpWidget(host(const Column(children: [
      ChatBubble(
        message: ChatMessage(username: 'lin', text: 'theirs', isMine: false),
      ),
      ChatBubble(
        message: ChatMessage(username: 'me', text: 'mine', isMine: true),
      ),
    ])));

    // Friend's name labels their bubble; my own name is not repeated.
    expect(find.text('lin'), findsOneWidget);
    expect(find.text('me'), findsNothing);
  });

  testWidgets('system message renders centered text, no sender label',
      (tester) async {
    await tester.pumpWidget(host(const ChatBubble(
      message: ChatMessage(
        username: '',
        text: 'lin joined the room',
        system: true,
      ),
    )));

    expect(find.text('lin joined the room'), findsOneWidget);
    // Not a bubble: no Align wrapper from the normal path.
    expect(find.byType(Align), findsNothing);
    expect(find.byType(Center), findsOneWidget);
  });

  testWidgets('mine aligns right, friend aligns left', (tester) async {
    await tester.pumpWidget(host(const Column(children: [
      ChatBubble(
        message: ChatMessage(username: 'me', text: 'mine', isMine: true),
      ),
      ChatBubble(
        message: ChatMessage(username: 'lin', text: 'theirs', isMine: false),
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
