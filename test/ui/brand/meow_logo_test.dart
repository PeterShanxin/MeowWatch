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

  testWidgets('MeowLogo leads with the mark by default', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(body: Center(child: MeowLogo())),
    ));
    final row = tester.widget<Row>(find.byType(Row).first);
    expect(row.children.first, isA<MeowLogoMark>());
    expect(row.children.last, isA<MeowWordmark>());
  });

  testWidgets('MeowLogo trails the mark when markLeading is false',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(
        body: Center(child: MeowLogo(markLeading: false)),
      ),
    ));
    final row = tester.widget<Row>(find.byType(Row).first);
    expect(row.children.first, isA<MeowWordmark>());
    expect(row.children.last, isA<MeowLogoMark>());
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
