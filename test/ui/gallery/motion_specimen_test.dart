import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
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
}
