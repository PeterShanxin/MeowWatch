import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/reactions/floating_reactions.dart';

void main() {
  testWidgets('spawns an emoji on stream event and clears when done',
      (tester) async {
    final controller = StreamController<String>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FloatingReactionsOverlay(emojis: controller.stream),
      ),
    ));

    controller.add('🎉');
    await tester.pump(); // process stream event
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('🎉'), findsOneWidget);

    // Let the ~2.4s animation finish; the emoji should remove itself.
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.text('🎉'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
