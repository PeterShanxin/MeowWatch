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

    testWidgets('fires onPressed on pointer up, not down (#218)',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(InstantTapIcon(
        icon: Icons.play_arrow_rounded,
        onPressed: () => pressed++,
      )));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(InstantTapIcon)));
      await tester.pump();
      expect(pressed, 0, reason: 'must not fire while the button is held');

      // Fires synchronously on release — no gesture-arena wait needed.
      await gesture.up();
      expect(pressed, 1,
          reason: 'must fire on release without waiting for the arena');
      await tester.pump(const Duration(milliseconds: 400));
      expect(pressed, 1);
    });

    testWidgets('dragging off the button before release cancels the press',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(InstantTapIcon(
        icon: Icons.play_arrow_rounded,
        onPressed: () => pressed++,
      )));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(InstantTapIcon)));
      await tester.pump();
      // Drag well outside the 48px tap target, then release.
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(pressed, 0, reason: 'release outside the button must not fire');
    });

    testWidgets(
        'dragging off and back onto the button before release still fires',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(InstantTapIcon(
        icon: Icons.play_arrow_rounded,
        onPressed: () => pressed++,
      )));

      final center = tester.getCenter(find.byType(InstantTapIcon));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      await gesture.moveTo(center);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(pressed, 1);
    });

    testWidgets('squashes on press, restores on release, fires on up',
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
      expect(pressed, 0);
      expect(_scale(tester), lessThan(1.0)); // squashed instantly on down

      await gesture.up();
      await tester.pump();
      expect(pressed, 1);
      expect(_scale(tester), 1.0); // restored
      await tester.pumpAndSettle(); // drain the scale animation
    });

    testWidgets('un-squashes while dragged off the button', (tester) async {
      await tester.pumpWidget(_wrap(InstantTapIcon(
        icon: Icons.play_arrow_rounded,
        onPressed: () {},
      )));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(InstantTapIcon)));
      await tester.pump();
      expect(_scale(tester), lessThan(1.0));

      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(_scale(tester), 1.0, reason: 'off the button = press abandoned');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('reduce motion: fires on up with no squash', (tester) async {
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
      expect(pressed, 0);
      expect(_scale(tester), 1.0); // no squash under reduce motion
      await gesture.up();
      expect(pressed, 1);
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
