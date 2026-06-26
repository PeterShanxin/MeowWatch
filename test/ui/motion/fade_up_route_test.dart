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
      page: const Scaffold(body: Text('room')),
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
      page: const Scaffold(body: Text('room')),
    )));
    await tester.pump();
    await tester.pump(); // no timed transition to wait on
    expect(find.text('room'), findsOneWidget);
  });
}
