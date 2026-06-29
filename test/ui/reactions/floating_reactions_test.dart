import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/reactions/floating_reactions.dart';

void main() {
  test('reaction pop overshoots without reduce motion, settles to 1', () {
    double peak(bool rm) {
      var p = 0.0;
      for (var i = 0; i <= 100; i++) {
        final v = reactionPopScale(i / 100, reduceMotion: rm);
        if (v > p) p = v;
      }
      return p;
    }

    expect(peak(false), greaterThan(1.05)); // the one squash-&-stretch
    expect(peak(true), lessThanOrEqualTo(1.0001)); // reduce motion: no overshoot
    // Both settle to a normal 1.0 by the time the pop is done.
    expect(reactionPopScale(1.0, reduceMotion: false), closeTo(1.0, 0.01));
    expect(reactionPopScale(1.0, reduceMotion: true), closeTo(1.0, 0.01));
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
}
