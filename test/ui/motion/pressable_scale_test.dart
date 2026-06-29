import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/motion/pressable_scale.dart';

/// The target scale handed to the inner [AnimatedScale] — what [PressableScale]
/// decides, independent of Flutter's animation timing.
double _scale(WidgetTester tester) => tester
    .widget<AnimatedScale>(find.descendant(
      of: find.byType(PressableScale),
      matching: find.byType(AnimatedScale),
    ))
    .scale;

Widget _host({required Widget child, bool reduceMotion = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: ReduceMotionScope(reduceMotion: reduceMotion, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('press scales the child down, release restores, tap fires',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(
      child: PressableScale(
        onPressed: () => taps++,
        child: const Text('Go'),
      ),
    ));
    expect(_scale(tester), 1.0);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Go')));
    await tester.pump();
    expect(_scale(tester), lessThan(1.0)); // pressed in

    await gesture.up();
    await tester.pump();
    expect(taps, 1);
    expect(_scale(tester), 1.0); // released back
  });

  testWidgets('reduce motion: no press scale, tap still fires', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(
      reduceMotion: true,
      child: PressableScale(
        onPressed: () => taps++,
        child: const Text('Go'),
      ),
    ));

    final gesture = await tester.startGesture(tester.getCenter(find.text('Go')));
    await tester.pump();
    expect(_scale(tester), 1.0); // no press scale under reduce motion

    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('disabled (null onPressed) does not scale', (tester) async {
    await tester.pumpWidget(_host(
      child: const PressableScale(child: Text('Go')),
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Go')));
    await tester.pump();
    expect(_scale(tester), 1.0);
    await gesture.up();
    await tester.pump();
  });
}
