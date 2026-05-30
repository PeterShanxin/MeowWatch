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
}
