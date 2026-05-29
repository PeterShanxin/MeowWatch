import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/theme/theme_swatches.dart';

void main() {
  testWidgets('tapping a swatch fires onChanged with that id', (tester) async {
    MeowThemeId? picked;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ThemeSwatches(
          current: MeowThemeId.cozy,
          onChanged: (id) => picked = id,
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('theme-swatch-noir')));
    expect(picked, MeowThemeId.noir);
  });

  testWidgets('renders one swatch per preset', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ThemeSwatches(current: MeowThemeId.cozy, onChanged: (_) {}),
      ),
    ));
    for (final id in MeowThemeId.values) {
      expect(find.byKey(Key('theme-swatch-${id.name}')), findsOneWidget);
    }
  });
}
