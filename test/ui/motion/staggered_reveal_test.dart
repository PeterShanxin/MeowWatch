import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/motion/staggered_reveal.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(home: Scaffold(body: child)),
    );

double _firstOpacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byType(Opacity).first).opacity;

void main() {
  testWidgets('held hidden until play, then cascades to fully present',
      (tester) async {
    await tester.pumpWidget(_host(const StaggeredReveal(
      play: false,
      holdHidden: true,
      children: [Text('a'), Text('b')],
    )));
    // Held invisible while the (simulated) reveal still covers it.
    expect(_firstOpacity(tester), 0);

    await tester.pumpWidget(_host(const StaggeredReveal(
      play: true,
      holdHidden: false,
      children: [Text('a'), Text('b')],
    )));
    await tester.pumpAndSettle(); // kick + settle the staggered cascade
    final opacities =
        tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity);
    expect(opacities.every((o) => o == 1.0), isTrue);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('reduce motion shows children present instantly (no hidden hold)',
      (tester) async {
    await tester.pumpWidget(_host(
      const StaggeredReveal(
        play: false,
        holdHidden: true,
        children: [Text('a')],
      ),
      reduceMotion: true,
    ));
    await tester.pump();
    expect(find.text('a'), findsOneWidget);
    final anyHidden = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .any((o) => o.opacity == 0);
    expect(anyHidden, isFalse);
  });

  testWidgets('no-reveal case shows children present, no cascade',
      (tester) async {
    await tester.pumpWidget(_host(const StaggeredReveal(
      play: false,
      holdHidden: false,
      children: [Text('a')],
    )));
    await tester.pump();
    expect(find.text('a'), findsOneWidget);
  });
}
