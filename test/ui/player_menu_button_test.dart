import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/player_menu_button.dart';

Widget _host(Widget child) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('menu is closed until the gear is tapped', (tester) async {
    await tester.pumpWidget(_host(PlayerMenuButton(
      roomCode: 'MEOW42',
      currentTheme: MeowThemeId.cozy,
      onThemeChanged: (_) {},
      onLeave: () {},
    )));
    expect(find.byKey(const Key('theme-swatch-noir')), findsNothing);

    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-swatch-noir')), findsOneWidget);
  });

  testWidgets('tapping a swatch fires onThemeChanged', (tester) async {
    MeowThemeId? picked;
    await tester.pumpWidget(_host(PlayerMenuButton(
      roomCode: 'MEOW42',
      currentTheme: MeowThemeId.cozy,
      onThemeChanged: (id) => picked = id,
      onLeave: () {},
    )));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-swatch-aurora')));
    expect(picked, MeowThemeId.aurora);
  });

  testWidgets('tapping Leave fires onLeave', (tester) async {
    var left = false;
    await tester.pumpWidget(_host(PlayerMenuButton(
      roomCode: 'MEOW42',
      currentTheme: MeowThemeId.cozy,
      onThemeChanged: (_) {},
      onLeave: () => left = true,
    )));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-menu-leave')));
    expect(left, isTrue);
  });

  testWidgets('shows the room code and copies it to the clipboard',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );

    await tester.pumpWidget(_host(PlayerMenuButton(
      roomCode: 'MEOW42',
      currentTheme: MeowThemeId.cozy,
      onThemeChanged: (_) {},
      onLeave: () {},
    )));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    expect(find.text('MEOW42'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-menu-room-code')));
    await tester.pump();
    expect(copied, 'MEOW42');
    expect(find.text('Copied!'), findsOneWidget);
  });
}
