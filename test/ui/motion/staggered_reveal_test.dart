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

  testWidgets('preserves child state across the hidden->playing handoff',
      (tester) async {
    // Regression: the held->playing handoff must not swap widget shape, or a
    // stateful child (e.g. ConnectScreen's continue-watching StreamBuilder)
    // gets torn down and repopulates from its initialData — cards pop in.
    _InitCounter.count = 0;
    await tester.pumpWidget(_host(StaggeredReveal(
      play: false,
      holdHidden: true,
      children: [_InitCounter()],
    )));
    expect(_InitCounter.count, 1); // mounted once while held

    await tester.pumpWidget(_host(StaggeredReveal(
      play: true,
      holdHidden: false,
      children: [_InitCounter()],
    )));
    await tester.pumpAndSettle();
    // Child was not torn down at the handoff, so initState ran exactly once.
    expect(_InitCounter.count, 1);
  });
}

/// A stateful child that counts how many times it is mounted, to prove the
/// hidden->playing handoff preserves (rather than recreates) its state.
class _InitCounter extends StatefulWidget {
  static int count = 0;
  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  @override
  void initState() {
    super.initState();
    _InitCounter.count++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
