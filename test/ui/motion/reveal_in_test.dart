import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/motion/reveal_in.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('starts faded/below and settles to fully present',
      (tester) async {
    await tester.pumpWidget(_host(const RevealIn(child: Text('hi'))));

    // First frame: not yet fully opaque.
    final start = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(start.opacity, lessThan(1.0));

    // After the animation: fully opaque, no residual offset.
    await tester.pump(const Duration(milliseconds: 400));
    final end = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(end.opacity, 1.0);
  });

  testWidgets('play:false holds the child hidden until play flips true',
      (tester) async {
    await tester.pumpWidget(_host(const RevealIn(play: false, child: Text('hi'))));
    await tester.pump(const Duration(milliseconds: 400)); // no animation runs
    final held = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(held.opacity, 0.0);
    expect(find.text('hi'), findsOneWidget); // mounted while held

    await tester.pumpWidget(_host(const RevealIn(play: true, child: Text('hi'))));
    await tester.pumpAndSettle();
    final shown = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(shown.opacity, 1.0);
  });

  testWidgets('reduce motion shows the child instantly at full opacity',
      (tester) async {
    await tester.pumpWidget(
      _host(const RevealIn(child: Text('hi')), reduceMotion: true),
    );
    await tester.pump(); // one frame, no animation scheduled
    final op = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(op.opacity, 1.0);
  });
}
