import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/ui/launch/launch_reveal.dart';

const _splash = Key('launch-reveal-splash');

/// A stand-in lobby that counts how many times its State is created, so a test
/// can prove the reveal reparents (not rebuilds) the lobby when it settles.
class _LobbyProbe extends StatefulWidget {
  const _LobbyProbe();

  static int initCount = 0;

  @override
  State<_LobbyProbe> createState() => _LobbyProbeState();
}

class _LobbyProbeState extends State<_LobbyProbe> {
  @override
  void initState() {
    super.initState();
    _LobbyProbe.initCount++;
  }

  @override
  Widget build(BuildContext context) => const Text('LOBBY');
}

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
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.byKey(_splash), findsNothing);
    expect(find.text('LOBBY'), findsOneWidget);
    expect(completed, 1);
  });

  testWidgets('preserves the lobby state across the settle (no rebuild flash)',
      (tester) async {
    _LobbyProbe.initCount = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        onComplete: () {},
        child: const _LobbyProbe(),
      ),
    ));
    // The lobby is mounted underneath the splash exactly once during the reveal.
    await tester.pump(const Duration(milliseconds: 100));
    expect(_LobbyProbe.initCount, 1);

    // After the reveal settles the splash is removed, but the lobby element is
    // reparented (stable GlobalKey) rather than torn down and rebuilt — so its
    // State survives and initState must NOT run a second time. A rebuild here is
    // what made ConnectScreen's streams reset to empty and flash a mini lobby.
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.byKey(_splash), findsNothing);
    expect(_LobbyProbe.initCount, 1);
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

  testWidgets('shows the given tip under the wordmark', (tester) async {
    await tester.pumpWidget(_host(
      LaunchReveal(
        onComplete: () {},
        tip: 'a custom hint',
        child: const Text('LOBBY'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('a custom hint'), findsOneWidget);
    // Settle so the controller finishes and the test tears down cleanly.
    await tester.pump(const Duration(milliseconds: 2900));
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
