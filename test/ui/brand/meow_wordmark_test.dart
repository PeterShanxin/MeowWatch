import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/brand/meow_wordmark.dart';

void main() {
  testWidgets('MeowWordmark shows the full plain text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(body: Center(child: MeowWordmark())),
    ));
    expect(find.text('MeowWatch'), findsOneWidget);
  });

  testWidgets('MeowWordmark colors Watch with the accent and uses Sora',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.aurora),
      home: const Scaffold(body: Center(child: MeowWordmark())),
    ));
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    // Text.rich wraps our span under a default-style root, so collect every
    // leaf TextSpan that carries text rather than assuming a flat shape.
    final leaves = <TextSpan>[];
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text != null) leaves.add(span);
        span.children?.forEach(walk);
      }
    }

    walk(rich.text);
    final meow = leaves.firstWhere((s) => s.text == 'Meow');
    final watch = leaves.firstWhere((s) => s.text == 'Watch');
    expect(watch.style!.color, const Color(0xFF7DF9C2)); // aurora accent
    expect(meow.style!.fontFamily, 'Sora');
  });
}
