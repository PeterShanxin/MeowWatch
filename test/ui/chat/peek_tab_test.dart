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

  AnimatedContainer tabBox(WidgetTester tester) => tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PeekTab),
          matching: find.byType(AnimatedContainer),
        ),
      );

  testWidgets('shows a slim 14px tab with a wider tap target', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(PeekTab(
      pulsing: false,
      unreadCount: 0,
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

  testWidgets('typing brightens + widens the tab and hides the idle icon (#53)',
      (tester) async {
    await tester.pumpWidget(host(PeekTab(
      pulsing: false,
      typing: true,
      unreadCount: 0,
      onTap: () {},
    )));
    // The dots animate forever — pump a frame, don't settle.
    await tester.pump(const Duration(milliseconds: 50));

    final box = tabBox(tester);
    expect((box.decoration as BoxDecoration).color, MeowColors.cozy.accent);

    final size = tester.getSize(find.descendant(
      of: find.byType(PeekTab),
      matching: find.byType(AnimatedContainer),
    ));
    expect(size.width, 22); // widened to fit the dots

    // The plain chat icon is replaced by the typing dots.
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
  });

  testWidgets('an unread count wins over typing dots (#53)', (tester) async {
    await tester.pumpWidget(host(PeekTab(
      pulsing: false,
      typing: true,
      unreadCount: 3,
      onTap: () {},
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // The badge takes priority when both apply.
    expect(find.text('3'), findsOneWidget);
  });
}
