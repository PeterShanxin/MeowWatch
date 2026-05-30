import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/peek_tab.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: child),
      );

  testWidgets('shows a slim 14px tab with a wider tap target', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(PeekTab(
      pulsing: false,
      onTap: () => tapped = true,
    )));

    // The visible tab stays slim (14px)...
    final visible = tester.getSize(find.descendant(
      of: find.byType(PeekTab),
      matching: find.byType(AnimatedContainer),
    ));
    expect(visible.width, 14);

    // ...but the tappable area is padded out so a near-miss still hits.
    final hit = tester.getSize(find.byType(PeekTab));
    expect(hit.width, greaterThanOrEqualTo(36));

    await tester.tap(find.byType(PeekTab));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
