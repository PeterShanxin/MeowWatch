import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart'; // themeDataFor + context.meow live here
import 'package:meowwatch/core/theme/meow_text.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/tokens/type_scale.dart';

Future<TextStyle> _styleUnder(WidgetTester tester, MeowThemeId id, TextStyle Function(BuildContext) pick) async {
  late TextStyle s;
  await tester.pumpWidget(MaterialApp(
    theme: themeDataFor(id),
    home: Builder(builder: (ctx) {
      s = pick(ctx);
      return const SizedBox();
    }),
  ));
  return s;
}

void main() {
  testWidgets('body uses scale size + theme primary color, no title font', (tester) async {
    final s = await _styleUnder(tester, MeowThemeId.cozy, (c) => c.meowText.body);
    expect(s.fontSize, TypeScale.body); // 13
    expect(s.color, MeowColors.cozy.textPrimary);
    expect(s.fontFamily, isNull);
  });

  testWidgets('title picks up Noir serif via titleFontFamily', (tester) async {
    final s = await _styleUnder(tester, MeowThemeId.noir, (c) => c.meowText.title);
    expect(s.fontSize, TypeScale.title); // 18
    expect(s.fontFamily, 'serif');
    expect(s.color, MeowColors.noir.textPrimary);
  });

  testWidgets('caption has no title font on Noir (not a heading)', (tester) async {
    final s = await _styleUnder(tester, MeowThemeId.noir, (c) => c.meowText.caption);
    expect(s.fontFamily, isNull);
  });
}
