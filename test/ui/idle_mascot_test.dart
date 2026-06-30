import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/idle_mascot.dart';

Widget _host({required Widget child, bool reduceMotion = false}) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: Center(
          child: ReduceMotionScope(reduceMotion: reduceMotion, child: child),
        ),
      ),
    );

void main() {
  testWidgets('renders and animates without throwing', (tester) async {
    await tester.pumpWidget(_host(child: const IdleMascot()));

    expect(find.byType(IdleMascot), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Advance through a full breath/blink cycle in steps; must not throw.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 800));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('breathes by default (keeps scheduling frames)', (tester) async {
    await tester.pumpWidget(_host(child: const IdleMascot()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('rests under reduce motion (no scheduled frames)',
      (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true, child: const IdleMascot()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('rests when animate is false', (tester) async {
    await tester.pumpWidget(_host(child: const IdleMascot(animate: false)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
