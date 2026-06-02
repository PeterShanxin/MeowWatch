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

PlayerMenuButton _button({
  ValueChanged<MeowThemeId>? onThemeChanged,
  VoidCallback? onLoadVideo,
  VoidCallback? onLeave,
  List<String>? members,
  bool chatAutoDim = true,
  ValueChanged<bool>? onChatAutoDimChanged,
  bool chatWakeOnMessage = false,
  ValueChanged<bool>? onChatWakeOnMessageChanged,
}) =>
    PlayerMenuButton(
      roomCode: 'MEOW42',
      members: members ?? const ['me', 'lin'],
      myUsername: 'me',
      currentTheme: MeowThemeId.cozy,
      onThemeChanged: onThemeChanged ?? (_) {},
      onLoadVideo: onLoadVideo ?? () {},
      onLeave: onLeave ?? () {},
      chatAutoDim: chatAutoDim,
      onChatAutoDimChanged: onChatAutoDimChanged ?? (_) {},
      chatWakeOnMessage: chatWakeOnMessage,
      onChatWakeOnMessageChanged: onChatWakeOnMessageChanged ?? (_) {},
    );

void main() {
  testWidgets('menu is closed until the gear is tapped', (tester) async {
    await tester.pumpWidget(_host(_button()));
    expect(find.byKey(const Key('theme-swatch-noir')), findsNothing);

    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-swatch-noir')), findsOneWidget);
  });

  testWidgets('tapping a swatch fires onThemeChanged', (tester) async {
    MeowThemeId? picked;
    await tester.pumpWidget(_host(_button(onThemeChanged: (id) => picked = id)));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-swatch-aurora')));
    expect(picked, MeowThemeId.aurora);
  });

  testWidgets('tapping Leave fires onLeave and closes the menu',
      (tester) async {
    var left = false;
    await tester.pumpWidget(_host(_button(onLeave: () => left = true)));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-menu-leave')));
    await tester.pumpAndSettle();
    expect(left, isTrue);
    // Menu dismissed — otherwise its FocusScope keeps trapping keyboard focus.
    expect(find.byKey(const Key('theme-swatch-noir')), findsNothing);
  });

  testWidgets('tapping Load video fires onLoadVideo and closes the menu',
      (tester) async {
    var loaded = false;
    await tester.pumpWidget(_host(_button(onLoadVideo: () => loaded = true)));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-menu-load')));
    await tester.pumpAndSettle();
    expect(loaded, isTrue);
    expect(find.byKey(const Key('theme-swatch-noir')), findsNothing);
  });

  testWidgets('lists room members with "(you)" for self', (tester) async {
    await tester.pumpWidget(_host(_button(members: const ['me', 'lin'])));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    expect(find.text('me (you)'), findsOneWidget);
    expect(find.text('lin'), findsOneWidget);
    expect(find.text('In the room (2)'), findsOneWidget);
  });

  testWidgets('copies the room code to the clipboard (no row reflow)',
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

    await tester.pumpWidget(_host(_button()));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    expect(find.text('MEOW42'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-menu-room-code')));
    await tester.pump();
    expect(copied, 'MEOW42');
    // Confirmation goes to a SnackBar; the row itself shows no "Copied!" text.
    expect(find.text('Copied!'), findsNothing);
    expect(find.textContaining('copied'), findsOneWidget);
  });

  testWidgets('tapping "Dim chat when idle" toggles onChatAutoDimChanged',
      (tester) async {
    bool? changed;
    await tester.pumpWidget(_host(_button(
      chatAutoDim: true,
      onChatAutoDimChanged: (v) => changed = v,
    )));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    expect(find.text('Dim chat when idle'), findsOneWidget);
    // Tapping the row flips the current (true) value to false.
    await tester.tap(find.text('Dim chat when idle'));
    expect(changed, isFalse);
  });

  testWidgets('tapping "Fully wake chat on message" toggles onChatWakeOnMessageChanged',
      (tester) async {
    bool? changed;
    await tester.pumpWidget(_host(_button(
      chatWakeOnMessage: false,
      onChatWakeOnMessageChanged: (v) => changed = v,
    )));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    expect(find.text('Fully wake chat on message'), findsOneWidget);
    // Tapping the row flips the current (false) value to true.
    await tester.tap(find.text('Fully wake chat on message'));
    expect(changed, isTrue);
  });

  testWidgets('hides the wake toggle while "Dim chat when idle" is off (#51)',
      (tester) async {
    await tester.pumpWidget(_host(_button(chatAutoDim: false)));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    // Auto-dim row is always there; the wake toggle is meaningless without it
    // and so is hidden.
    expect(find.text('Dim chat when idle'), findsOneWidget);
    expect(find.text('Fully wake chat on message'), findsNothing);
  });
}
