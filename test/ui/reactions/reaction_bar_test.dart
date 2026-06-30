import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/reactions/reaction_bar.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: Center(
          child: ReduceMotionScope(reduceMotion: reduceMotion, child: child),
        ),
      ),
    );

void main() {
  testWidgets('palette is hidden until the toggle is tapped', (tester) async {
    await tester.pumpWidget(_host(ReactionBar(onReact: (_) {})));
    expect(find.byKey(const Key('reaction-❤️')), findsNothing);

    await tester.tap(find.byKey(const Key('reaction-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reaction-❤️')), findsOneWidget);
  });

  testWidgets('tapping an emoji fires onReact and collapses', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(ReactionBar(onReact: (e) => picked = e)));

    await tester.tap(find.byKey(const Key('reaction-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reaction-🎉')));
    await tester.pumpAndSettle();

    expect(picked, '🎉');
    expect(find.byKey(const Key('reaction-🎉')), findsNothing);
  });

  testWidgets('reduce motion: palette opens instantly, no size animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(ReactionBar(onReact: (_) {}), reduceMotion: true),
    );
    // Animated mode wraps the palette in an AnimatedSize; reduce motion must not.
    expect(find.byType(AnimatedSize), findsNothing);

    await tester.tap(find.byKey(const Key('reaction-toggle')));
    await tester.pump(); // a single frame — no time elapsed
    expect(
      find.byKey(const Key('reaction-❤️')),
      findsOneWidget,
      reason: 'palette is fully present in one frame, with no growth animation',
    );
    expect(find.byType(AnimatedSize), findsNothing);
  });

  testWidgets('animated mode wraps the palette in an AnimatedSize', (
    tester,
  ) async {
    await tester.pumpWidget(_host(ReactionBar(onReact: (_) {})));
    expect(find.byType(AnimatedSize), findsOneWidget);
  });
}
