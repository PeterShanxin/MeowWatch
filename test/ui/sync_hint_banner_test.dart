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

void main() {
  testWidgets('animates a notice in, then out (no hard cut)', (tester) async {
    final text = ValueNotifier<String?>(null);
    addTearDown(text.dispose);
    await tester.pumpWidget(_host(text));
    expect(find.text('hi'), findsNothing);

    text.value = 'hi';
    await tester.pump(); // start the in-animation
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);

    text.value = null;
    await tester.pump(const Duration(milliseconds: 50)); // mid out-animation
    expect(find.text('hi'), findsOneWidget,
        reason: 'still sliding/fading out, not hard-cut');
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsNothing);
  });

  testWidgets('cross-fades between two notices', (tester) async {
    final text = ValueNotifier<String?>('first');
    addTearDown(text.dispose);
    await tester.pumpWidget(_host(text));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    text.value = 'second';
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('first'), findsOneWidget); // outgoing still present
    expect(find.text('second'), findsOneWidget); // incoming present
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('reduce motion: instant swap, no lingering exit', (tester) async {
    final text = ValueNotifier<String?>('hi');
    addTearDown(text.dispose);
    await tester.pumpWidget(_host(text, reduceMotion: true));
    await tester.pump();
    expect(find.text('hi'), findsOneWidget);

    text.value = null;
    await tester.pump();
    expect(find.text('hi'), findsNothing); // gone instantly
  });
}
