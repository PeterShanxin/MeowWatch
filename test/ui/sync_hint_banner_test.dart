import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/sync_hint_banner.dart';

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(find.descendant(
      of: find.byType(SyncHintBanner),
      matching: find.byType(Opacity),
    ))
    .opacity;

double _offsetY(WidgetTester tester) => tester
    .widget<Transform>(find.descendant(
      of: find.byType(SyncHintBanner),
      matching: find.byType(Transform),
    ))
    .transform
    .getTranslation()
    .y;

Widget _host({required Widget child, bool reduceMotion = false}) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: Center(
          child: ReduceMotionScope(reduceMotion: reduceMotion, child: child),
        ),
      ),
    );

void main() {
  testWidgets('slides down + fades in, then settles', (tester) async {
    await tester.pumpWidget(_host(child: const SyncHintBanner(text: 'hi')));
    await tester.pump(); // first frame: entrance just started

    expect(_opacity(tester), lessThan(1.0)); // fading in
    expect(_offsetY(tester), lessThan(0.0)); // started above its resting spot

    await tester.pumpAndSettle();
    expect(_opacity(tester), 1.0);
    expect(_offsetY(tester), closeTo(0.0, 0.001)); // settled into place
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('reduce motion: present immediately, no slide', (tester) async {
    await tester.pumpWidget(
      _host(reduceMotion: true, child: const SyncHintBanner(text: 'hi')),
    );
    await tester.pump();

    expect(_opacity(tester), 1.0);
    expect(_offsetY(tester), closeTo(0.0, 0.001));
  });
}
