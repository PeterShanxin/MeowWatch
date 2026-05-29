import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/idle_mascot.dart';

void main() {
  testWidgets('idle mascot golden (eyes open frame)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(
        backgroundColor: Color(0xFF1A1410),
        body: Center(child: IdleMascot(size: 200)),
      ),
    ));
    // Land on an eyes-open, mid-breath frame (t≈0.5 of the 3600ms loop).
    await tester.pump(const Duration(milliseconds: 1800));
    await expectLater(
      find.byType(IdleMascot),
      matchesGoldenFile('goldens/idle_mascot.png'),
    );
  });
}
