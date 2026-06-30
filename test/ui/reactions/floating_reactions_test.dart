import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/reactions/floating_reactions.dart';

void main() {
  test('reaction pop overshoots, then settles to 1', () {
    var peak = 0.0;
    for (var i = 0; i <= 100; i++) {
      final v = reactionPopScale(i / 100);
      if (v > peak) peak = v;
    }

    expect(peak, greaterThan(1.05)); // the one squash-&-stretch
    expect(reactionPopScale(1.0), closeTo(1.0, 0.01)); // settles to a normal 1.0
  });

  test('reaction arc drifts sideways across the rise, none under reduce motion',
      () {
    // Starts at origin, drifts toward the target by the end.
    expect(reactionArcX(0, 40), closeTo(0, 0.01));
    expect(reactionArcX(1, 40), closeTo(40, 0.01));
    expect(reactionArcX(0.5, 40), greaterThan(0));
  });

  testWidgets('spawns an emoji on stream event and clears when done',
      (tester) async {
    final controller = StreamController<String>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FloatingReactionsOverlay(emojis: controller.stream),
      ),
    ));

    controller.add('🎉');
    await tester.pump(); // process stream event
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('🎉'), findsOneWidget);

    // Let the ~2.4s animation finish; the emoji should remove itself.
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.text('🎉'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion: the burst is static — no rise, drift, or fade',
      (tester) async {
    final controller = StreamController<String>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReduceMotionScope(
          reduceMotion: true,
          child: FloatingReactionsOverlay(emojis: controller.stream),
        ),
      ),
    ));

    controller.add('🎉');
    await tester.pump(); // process stream event
    await tester.pump(const Duration(milliseconds: 100));
    final early = tester.getTopLeft(find.text('🎉'));

    // Partway through the lifetime it must not have moved (no animated rise/drift).
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getTopLeft(find.text('🎉')), early,
        reason: 'reduce motion presents the burst settled, with no movement');

    // It still self-removes when the lifetime elapses.
    await tester.pump(const Duration(milliseconds: 1700));
    expect(find.text('🎉'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
