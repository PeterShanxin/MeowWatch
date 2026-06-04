import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
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
        body: Stack(
          children: [
            ChatOverlay(
              messages: const [],
              collapsed: false,
              corner: ChatCorner.bottomLeft,
              onSend: (_) {},
              onToggleCollapsed: () {},
              onSnap: (_) {},
              onResize: onResize,
              onResetSize: onResetSize,
            ),
          ],
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

  testWidgets('no dock hints appear while resizing via a grip', (tester) async {
    // Regression guard for issue #42: a resize reuses the free-floating render
    // path, and the dock-hint layer over a resizing card flashed a white
    // screen. The hints must stay hidden for the whole grip drag.
    await tester.pumpWidget(_host(onResize: (_) {}, onResetSize: () {}));
    final grip = find.byKey(const ValueKey('chat-resize-grip-bottomRight'));
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    expect(find.byIcon(Icons.north_west), findsNothing);
    expect(find.byIcon(Icons.south_east), findsNothing);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('control tooltips are present', (tester) async {
    await tester.pumpWidget(_host(onResize: (_) {}, onResetSize: () {}));
    expect(find.byTooltip('Reset size'), findsOneWidget);
    expect(find.byTooltip('Hide chat'), findsOneWidget);
    expect(find.byTooltip('Drag to move'), findsOneWidget);
    expect(find.byTooltip('Drag to resize'), findsWidgets); // one per corner
  });
}
