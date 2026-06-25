import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/ui/launch/launch_reveal.dart';

const _splash = Key('launch-reveal-splash');

Widget _host(
  Widget reveal, {
  bool reduceMotion = false,
}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: themeDataFor(MeowThemeId.aurora),
        home: Scaffold(body: reveal),
      ),
    );

void main() {
  testWidgets('plays then settles to the child and removes the splash',
      (tester) async {
    var completed = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        onComplete: () => completed++,
        child: const Text('LOBBY'),
      ),
    ));

    // Mid-reveal: the splash is up.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(_splash), findsOneWidget);
    expect(completed, 0);

    // After the full timeline: splash gone, child present, completed once.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(_splash), findsNothing);
    expect(find.text('LOBBY'), findsOneWidget);
    expect(completed, 1);
  });

  testWidgets('any tap skips straight to the settled lobby', (tester) async {
    var completed = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        onComplete: () => completed++,
        child: const Text('LOBBY'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_splash), findsOneWidget);

    await tester.tap(find.byKey(_splash));
    await tester.pump(); // start the fast skip
    await tester.pump(const Duration(milliseconds: 200)); // finish it
    expect(find.byKey(_splash), findsNothing);
    expect(completed, 1);
  });

  testWidgets('reduce motion shows the lobby immediately, no splash',
      (tester) async {
    var completed = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        onComplete: () => completed++,
        child: const Text('LOBBY'),
      ),
      reduceMotion: true,
    ));
    await tester.pump(); // run the post-frame complete
    expect(find.byKey(_splash), findsNothing);
    expect(find.text('LOBBY'), findsOneWidget);
    expect(completed, 1);
  });

  testWidgets('disabled passes the child straight through', (tester) async {
    var completed = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        enabled: false,
        onComplete: () => completed++,
        child: const Text('LOBBY'),
      ),
    ));
    await tester.pump();
    expect(find.byKey(_splash), findsNothing);
    expect(find.text('LOBBY'), findsOneWidget);
    expect(completed, 1);
  });
}
