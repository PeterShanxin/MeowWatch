import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';

void main() {
  testWidgets('context.meow returns the active extension', (tester) async {
    late MeowColors seen;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.noir),
      home: Builder(builder: (context) {
        seen = context.meow;
        return const SizedBox();
      }),
    ));
    expect(seen.accent, MeowColors.noir.accent);
  });

  test('themeDataFor seeds the ColorScheme from the preset accent', () {
    final t = themeDataFor(MeowThemeId.aurora);
    expect(t.extension<MeowColors>(), MeowColors.aurora);
    expect(t.useMaterial3, isTrue);
    expect(t.brightness, Brightness.dark);
  });
}
