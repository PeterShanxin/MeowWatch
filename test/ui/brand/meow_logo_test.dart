import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/brand/meow_logo.dart';
import 'package:meowwatch/ui/brand/meow_logo_mark.dart';
import 'package:meowwatch/ui/brand/meow_wordmark.dart';

void main() {
  testWidgets('MeowLogo composes the mark and wordmark (horizontal)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(body: Center(child: MeowLogo())),
    ));
    expect(find.byType(MeowLogoMark), findsOneWidget);
    expect(find.byType(MeowWordmark), findsOneWidget);
    expect(find.byType(Row), findsWidgets);
  });

  testWidgets('MeowLogo stacks vertically when axis is vertical',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(
        body: Center(child: MeowLogo(axis: Axis.vertical)),
      ),
    ));
    expect(find.byType(Column), findsWidgets);
    expect(find.byType(MeowLogoMark), findsOneWidget);
    expect(find.byType(MeowWordmark), findsOneWidget);
  });
}
