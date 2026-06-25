import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/brand/meow_logo_mark.dart';

void main() {
  testWidgets('MeowLogoMark renders at the given size without error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(body: Center(child: MeowLogoMark(size: 80))),
    ));
    final box = tester.getSize(find.byType(MeowLogoMark));
    expect(box, const Size(80, 80));
  });

  testWidgets('MeowLogoMark uses the theme accent when no color is given',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.aurora),
      home: const Scaffold(body: Center(child: MeowLogoMark(size: 40))),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('MeowLogoMark golden (cozy)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(
        backgroundColor: Color(0xFF1A1410),
        body: Center(child: MeowLogoMark(size: 200)),
      ),
    ));
    await expectLater(
      find.byType(MeowLogoMark),
      matchesGoldenFile('goldens/meow_logo_mark_cozy.png'),
    );
  });
}
