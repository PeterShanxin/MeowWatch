import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/motion/fade_up_route.dart';

void main() {
  testWidgets('fades + slides the page in and reverses on pop', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('lobby')),
    ));

    unawaited(navKey.currentState!.push(fadeUpRoute<void>(
      reduceMotion: false,
      builder: (_) => const Scaffold(body: Text('room')),
    )));
    await tester.pump(); // start the transition
    await tester.pump(const Duration(milliseconds: 50)); // mid-transition
    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.byType(FadeTransition), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('room'), findsOneWidget);

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('lobby'), findsOneWidget);
  });

  testWidgets('reduce motion is an instant cut', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('lobby')),
    ));

    unawaited(navKey.currentState!.push(fadeUpRoute<void>(
      reduceMotion: true,
      builder: (_) => const Scaffold(body: Text('room')),
    )));
    await tester.pump();
    await tester.pump(); // no timed transition to wait on
    expect(find.text('room'), findsOneWidget);
  });

  testWidgets('rebuilds the pushed page when the host rebuilds', (tester) async {
    // Regression guard: the page must track live host state (e.g. the theme the
    // in-room gear switches). A pre-built widget would freeze at push time; a
    // builder is re-invoked on the route's changedExternalState.
    final hostKey = GlobalKey<_ThemeHostState>();
    await tester.pumpWidget(_ThemeHost(key: hostKey));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('page=A'), findsOneWidget);

    // Bump host state — MaterialApp/Navigator rebuilds, so the route must
    // rebuild its page from the latest value.
    hostKey.currentState!.bump();
    await tester.pumpAndSettle();
    expect(find.text('page=B'), findsOneWidget);
    expect(find.text('page=A'), findsNothing);
  });
}

/// A minimal host that owns a label and pushes a [fadeUpRoute] whose builder
/// reads that label, so the test can prove the pushed page rebuilds when the
/// host's state changes.
class _ThemeHost extends StatefulWidget {
  const _ThemeHost({super.key});
  @override
  State<_ThemeHost> createState() => _ThemeHostState();
}

class _ThemeHostState extends State<_ThemeHost> {
  final _navKey = GlobalKey<NavigatorState>();
  String _label = 'A';

  void bump() => setState(() => _label = 'B');

  void _push() {
    unawaited(_navKey.currentState!.push(fadeUpRoute<void>(
      reduceMotion: true,
      builder: (_) => Scaffold(body: Text('page=$_label')),
    )));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      home: Scaffold(
        body: Center(
          child: ElevatedButton(onPressed: _push, child: const Text('go')),
        ),
      ),
    );
  }
}
