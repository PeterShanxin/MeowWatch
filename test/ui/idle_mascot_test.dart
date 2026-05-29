import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/idle_mascot.dart';

void main() {
  testWidgets('renders and animates without throwing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(body: Center(child: IdleMascot())),
    ));

    expect(find.byType(IdleMascot), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Advance through a full breath/blink cycle in steps; must not throw.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 800));
    }
    expect(tester.takeException(), isNull);
  });
}
