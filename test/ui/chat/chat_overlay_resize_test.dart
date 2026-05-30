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
              myUsername: 'me',
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
