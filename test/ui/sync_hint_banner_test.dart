import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/sync_hint_banner.dart';

Widget _host(ValueNotifier<String?> text, {bool reduceMotion = false}) =>
    MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: Center(
          child: ReduceMotionScope(
            reduceMotion: reduceMotion,
            child: ValueListenableBuilder<String?>(
              valueListenable: text,
              builder: (_, t, _) => SyncHintBanner(text: t),
            ),
          ),
        ),
      ),
    );

// The vertical slide offset of the pill carrying [text], at the current frame.
// Non-zero while it's still arriving; zero once settled.
double _slideDy(WidgetTester tester, String text) => tester
    .widget<SlideTransition>(
      find
          .ancestor(of: find.text(text), matching: find.byType(SlideTransition))
          .first,
    )
    .position
    .value
    .dy;

void main() {
  testWidgets('a fresh notice physically slides in, then settles', (
    tester,
  ) async {
    final text = ValueNotifier<String?>(null);
    addTearDown(text.dispose);
    await tester.pumpWidget(_host(text));

    text.value = 'hi';
    await tester.pump(); // mount the pill; intro at 0
    await tester.pump(const Duration(milliseconds: 80)); // mid intro
    expect(
      _slideDy(tester, 'hi'),
      lessThan(0.0),
      reason: 'still sliding down from above — not hard-cut in',
    );

    await tester.pumpAndSettle();
    expect(_slideDy(tester, 'hi'), 0.0, reason: 'settled at rest');
  });

  testWidgets('a delayed first animation frame still shows entrance motion', (
    tester,
  ) async {
    final text = ValueNotifier<String?>(null);
    addTearDown(text.dispose);
    await tester.pumpWidget(_host(text));

    text.value = 'late load';
    await tester.pump(); // mount the pill; intro at 0
    await tester.pump(const Duration(milliseconds: 500)); // janky first frame
    expect(
      _slideDy(tester, 'late load'),
      lessThan(0.0),
      reason: 'a late first tick must not make the entrance finish off-screen',
    );

    await tester.pumpAndSettle();
    expect(_slideDy(tester, 'late load'), 0.0, reason: 'settled at rest');
  });

  testWidgets('animates a notice in, then out (no hard cut)', (tester) async {
    final text = ValueNotifier<String?>(null);
    addTearDown(text.dispose);
    await tester.pumpWidget(_host(text));
    expect(find.text('hi'), findsNothing);

    text.value = 'hi';
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);

    text.value = null;
    await tester.pump(const Duration(milliseconds: 50)); // mid out-animation
    expect(
      find.text('hi'),
      findsOneWidget,
      reason: 'still fading out, not hard-cut',
    );
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsNothing);
  });

  testWidgets('the incoming notice slides in even when swapping from another', (
    tester,
  ) async {
    final text = ValueNotifier<String?>('first');
    addTearDown(text.dispose);
    await tester.pumpWidget(_host(text));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    text.value = 'second';
    await tester.pump(); // mount the incoming pill
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('first'), findsOneWidget); // outgoing still fading
    expect(find.text('second'), findsOneWidget); // incoming present
    expect(
      _slideDy(tester, 'second'),
      lessThan(0.0),
      reason: 'incoming notice slides in over the outgoing one, not in place',
    );

    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('reduce motion: instant present, no lingering exit, no timers', (
    tester,
  ) async {
    final text = ValueNotifier<String?>('hi');
    addTearDown(text.dispose);
    await tester.pumpWidget(_host(text, reduceMotion: true));
    await tester.pump();
    expect(find.text('hi'), findsOneWidget);
    expect(_slideDy(tester, 'hi'), 0.0, reason: 'present instantly, no slide');

    text.value = null;
    await tester.pump();
    expect(find.text('hi'), findsNothing); // gone instantly
  });
}
