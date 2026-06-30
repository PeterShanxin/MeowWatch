import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/instant_tap_icon.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

double _scale(WidgetTester tester) => tester
    .widget<AnimatedScale>(find.descendant(
      of: find.byType(InstantTapIcon),
      matching: find.byType(AnimatedScale),
    ))
    .scale;

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

    testWidgets('squashes on press, restores on release, still fires on down',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(InstantTapIcon(
        icon: Icons.play_arrow_rounded,
        onPressed: () => pressed++,
      )));
      expect(_scale(tester), 1.0);

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(InstantTapIcon)));
      await tester.pump();
      expect(pressed, 1); // fired on down, no arena wait
      expect(_scale(tester), lessThan(1.0)); // squashed

      await gesture.up();
      await tester.pump();
      expect(_scale(tester), 1.0); // restored
      await tester.pumpAndSettle(); // drain the scale animation
    });

    testWidgets('reduce motion: fires on down with no squash', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ReduceMotionScope(
              reduceMotion: true,
              child: InstantTapIcon(
                icon: Icons.play_arrow_rounded,
                onPressed: () => pressed++,
              ),
            ),
          ),
        ),
      ));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(InstantTapIcon)));
      await tester.pump();
      expect(pressed, 1);
      expect(_scale(tester), 1.0); // no squash under reduce motion
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Enter activates it when focused (keyboard parity)',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(InstantTapIcon(
        icon: Icons.play_arrow_rounded,
        onPressed: () => pressed++,
      )));

      // Move focus to the first focusable in the scope — the button's
      // FocusableActionDetector — then activate it with Enter.
      FocusScope.of(tester.element(find.byType(InstantTapIcon))).nextFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(pressed, 1);
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
