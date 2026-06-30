import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/gallery/gallery_sections.dart';

void main() {
  // The duration/easing racers loop forever — never pumpAndSettle here; pump
  // fixed durations instead.
  Widget host() => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: const Scaffold(
          body: SingleChildScrollView(child: MotionSpecimen()),
        ),
      );

  testWidgets('renders duration + easing racers and the token chips',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('DURATIONS'), findsOneWidget);
    expect(find.text('EASINGS'), findsOneWidget);

    // Easing rows name the curve + its bezier.
    expect(find.text('easeOutCubic'), findsOneWidget);
    expect(find.text('easeInOut'), findsOneWidget);
    expect(find.text('(.215, .61, .355, 1)'), findsOneWidget);

    // The token chips still name each value (also appears as a racer label).
    expect(find.text('stagger · 55ms'), findsOneWidget);
    expect(find.textContaining('fast · 120ms'), findsWidgets);
  });

  testWidgets('racers keep animating without throwing', (tester) async {
    await tester.pumpWidget(host());
    // Advance well past the longest racer period a few times.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
  });

  // The principle loops also run forever — pump fixed durations, never settle.
  Widget principlesHost({bool reduceMotion = false}) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: ReduceMotionScope(
            reduceMotion: reduceMotion,
            child: const SingleChildScrollView(child: MotionPrinciplesSpecimen()),
          ),
        ),
      );

  testWidgets('motion principles: the four named specimens render and loop',
      (tester) async {
    await tester.pumpWidget(principlesHost());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Anticipation'), findsOneWidget);
    expect(find.text('Overshoot'), findsOneWidget);
    expect(find.text('Squash & stretch'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);

    // Advance past the loops a few times — they must keep running cleanly.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion principles: static under reduce motion (loops settle)',
      (tester) async {
    await tester.pumpWidget(principlesHost(reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Anticipation'), findsOneWidget);
    // Nothing loops under reduce motion, so the tree settles (no infinite
    // animation). pumpAndSettle would hang if a principle kept looping.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
