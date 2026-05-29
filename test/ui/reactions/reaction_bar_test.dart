import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/reactions/reaction_bar.dart';

Widget _host(Widget child) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(body: Center(child: child)),
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
}
