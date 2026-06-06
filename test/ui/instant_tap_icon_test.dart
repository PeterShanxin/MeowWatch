import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/instant_tap_icon.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('InstantTapIcon', () {
    testWidgets('renders the given icon', (tester) async {
      await tester.pumpWidget(_wrap(InstantTapIcon(
        icon: Icons.play_arrow_rounded,
        onPressed: () {},
      )));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('fires onPressed on pointer down (no arena wait)',
        (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(InstantTapIcon(
        icon: Icons.play_arrow_rounded,
        onPressed: () => pressed = true,
      )));

      // Press down only — the callback must fire before pointer-up, proving it
      // does not wait for the gesture arena to resolve.
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(InstantTapIcon)));
      expect(pressed, isTrue);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('absorbs tap and double-tap from an ancestor GestureDetector',
        (tester) async {
      var ancestorTaps = 0;
      var ancestorDoubleTaps = 0;
      var pressed = 0;

      await tester.pumpWidget(_wrap(GestureDetector(
        onTap: () => ancestorTaps++,
        onDoubleTap: () => ancestorDoubleTaps++,
        child: InstantTapIcon(
          icon: Icons.play_arrow_rounded,
          onPressed: () => pressed++,
        ),
      )));

      await tester.tap(find.byType(InstantTapIcon));
      await tester.pump(const Duration(milliseconds: 400));

      expect(pressed, 1);
      expect(ancestorTaps, 0, reason: 'icon must claim the tap');
      expect(ancestorDoubleTaps, 0);
    });
  });
}
