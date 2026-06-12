import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/log_level.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/player_menu_button.dart';

Widget _host(Widget child) => MaterialApp(
  theme: themeDataFor(MeowThemeId.cozy),
  home: Scaffold(body: child),
);

PlayerMenuButton _button({
  String? nowPlaying = 'Bocchi the Rock - 01.mkv',
  ValueChanged<MeowThemeId>? onThemeChanged,
  VoidCallback? onLoadVideo,
  VoidCallback? onLeave,
  List<String>? members,
  String myUsername = 'me',
  String? myDisplayName,
  bool chatAutoDim = true,
  ValueChanged<bool>? onChatAutoDimChanged,
  bool chatWakeOnMessage = false,
  ValueChanged<bool>? onChatWakeOnMessageChanged,
  double chatIdleDim = 0.5,
  ValueChanged<double>? onChatIdleDimChanged,
  String primarySoundId = 'marimba',
  ValueChanged<String>? onPrimarySoundChanged,
  String secondarySoundId = 'low_thud',
  ValueChanged<String>? onSecondarySoundChanged,
  ValueChanged<String>? onPreviewSound,
  LogLevel logLevel = LogLevel.verbose,
  ValueChanged<LogLevel>? onLogLevelChanged,
  VoidCallback? onExportLogs,
}) => PlayerMenuButton(
  roomCode: 'MEOW42',
  nowPlaying: nowPlaying,
  members: members ?? const ['me', 'lin'],
  myUsername: myUsername,
  myDisplayName: myDisplayName ?? myUsername,
  currentTheme: MeowThemeId.cozy,
  onThemeChanged: onThemeChanged ?? (_) {},
  onLoadVideo: onLoadVideo ?? () {},
  onLeave: onLeave ?? () {},
  chatAutoDim: chatAutoDim,
  onChatAutoDimChanged: onChatAutoDimChanged ?? (_) {},
  chatWakeOnMessage: chatWakeOnMessage,
  onChatWakeOnMessageChanged: onChatWakeOnMessageChanged ?? (_) {},
  chatIdleDim: chatIdleDim,
  onChatIdleDimChanged: onChatIdleDimChanged ?? (_) {},
  primarySoundId: primarySoundId,
  onPrimarySoundChanged: onPrimarySoundChanged ?? (_) {},
  secondarySoundId: secondarySoundId,
  onSecondarySoundChanged: onSecondarySoundChanged ?? (_) {},
  onPreviewSound: onPreviewSound ?? (_) {},
  logLevel: logLevel,
  onLogLevelChanged: onLogLevelChanged ?? (_) {},
  onExportLogs: onExportLogs ?? () {},
);

/// Open the gear and expand the collapsible Settings section.
///
/// The expanded Settings popover is taller than the default 600px test
/// viewport; production keeps the lower controls reachable by scrolling, but
/// these tests assert taps land directly, so size the window to a realistic
/// desktop height first so the whole menu fits without scrolling.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.tap(find.byKey(const Key('player-menu-gear')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('player-menu-settings')));
  await tester.pumpAndSettle();
}

/// Scroll [finder] into the (now scrollable) popover before tapping it, so the
/// hit-test lands on the control rather than the viewport surface.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

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
    await tester.pumpWidget(
      _host(_button(onThemeChanged: (id) => picked = id)),
    );
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-swatch-aurora')));
    expect(picked, MeowThemeId.aurora);
  });

  testWidgets('tapping Leave fires onLeave and closes the menu', (
    tester,
  ) async {
    var left = false;
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(_button(onLeave: () => left = true)));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('player-menu-leave')));
    expect(left, isTrue);
    // Menu dismissed — otherwise its FocusScope keeps trapping keyboard focus.
    expect(find.byKey(const Key('theme-swatch-noir')), findsNothing);
  });

  testWidgets('tapping Load video fires onLoadVideo and closes the menu', (
    tester,
  ) async {
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

  testWidgets('me-row shows the requested name, not a reconnect suffix (#107)', (
    tester,
  ) async {
    // After a fast reconnect the server hands back a deduped wire name
    // ("meowPEOW_"), and the phantom ghost of our old name is forwarded as a
    // peer ("meowPEOW"). The member list keeps wire identities (so isMe matches
    // the chat echo / self-filter and the phantom doesn't collide), but our own
    // row must render the clean name we chose — never the transient suffix.
    await tester.pumpWidget(
      _host(
        _button(
          members: const ['meowPEOW_', 'meowPEOW'],
          myUsername: 'meowPEOW_',
          myDisplayName: 'meowPEOW',
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    expect(find.text('meowPEOW (you)'), findsOneWidget); // us, clean name
    expect(find.text('meowPEOW_ (you)'), findsNothing); // suffix never shown
    expect(find.text('meowPEOW'), findsOneWidget); // phantom peer, untagged
    expect(find.textContaining('(you)'), findsOneWidget); // exactly one "me"
  });

  testWidgets('copies the room code to the clipboard (no row reflow)', (
    tester,
  ) async {
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

  testWidgets('shows the currently playing media name (#133)', (tester) async {
    await tester.pumpWidget(
      _host(_button(nowPlaying: 'Frieren - 12.mkv')),
    );
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Frieren - 12.mkv'), findsOneWidget);
  });

  testWidgets('shows an empty-state line when no media is loaded (#133)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_button(nowPlaying: null)));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Nothing loaded yet'), findsOneWidget);
  });

  testWidgets('long media names ellipsize without overflowing (#133)', (
    tester,
  ) async {
    const longName =
        'A.Very.Long.Episode.Title.That.Should.Not.Break.The.Menu.'
        'Layout.S01E01.1080p.WEB-DL.x265.mkv';
    await tester.pumpWidget(_host(_button(nowPlaying: longName)));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    // The row renders (clipped via ellipsis) rather than throwing an overflow.
    expect(find.byKey(const Key('player-menu-now-playing')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings is collapsed until its header is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_button()));
    await tester.tap(find.byKey(const Key('player-menu-gear')));
    await tester.pumpAndSettle();

    // The header shows, but its controls are hidden until expanded.
    expect(find.byKey(const Key('player-menu-settings')), findsOneWidget);
    expect(find.text('Dim chat when idle'), findsNothing);

    await tester.tap(find.byKey(const Key('player-menu-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Dim chat when idle'), findsOneWidget);
  });

  testWidgets('tapping "Dim chat when idle" toggles onChatAutoDimChanged', (
    tester,
  ) async {
    bool? changed;
    await tester.pumpWidget(
      _host(
        _button(chatAutoDim: true, onChatAutoDimChanged: (v) => changed = v),
      ),
    );
    await _openSettings(tester);

    expect(find.text('Dim chat when idle'), findsOneWidget);
    // Tapping the row flips the current (true) value to false.
    await _tap(tester, find.text('Dim chat when idle'));
    expect(changed, isFalse);
  });

  testWidgets(
    'tapping "Fully wake chat on message" toggles onChatWakeOnMessageChanged',
    (tester) async {
      bool? changed;
      await tester.pumpWidget(
        _host(
          _button(
            chatWakeOnMessage: false,
            onChatWakeOnMessageChanged: (v) => changed = v,
          ),
        ),
      );
      await _openSettings(tester);

      expect(find.text('Fully wake chat on message'), findsOneWidget);
      // Tapping the row flips the current (false) value to true.
      await _tap(tester, find.text('Fully wake chat on message'));
      expect(changed, isTrue);
    },
  );

  testWidgets(
    'hides the wake toggle + dim slider while "Dim chat when idle" is off (#51)',
    (tester) async {
      await tester.pumpWidget(_host(_button(chatAutoDim: false)));
      await _openSettings(tester);

      // Auto-dim row is always there; the wake toggle and dim slider are
      // meaningless without it and so are hidden.
      expect(find.text('Dim chat when idle'), findsOneWidget);
      expect(find.text('Fully wake chat on message'), findsNothing);
      expect(find.text('Dimmed chat readability'), findsNothing);
    },
  );

  testWidgets('picking a diagnostic-log level fires onLogLevelChanged', (
    tester,
  ) async {
    LogLevel? picked;
    await tester.pumpWidget(
      _host(
        _button(
          logLevel: LogLevel.verbose,
          onLogLevelChanged: (v) => picked = v,
        ),
      ),
    );
    await _openSettings(tester);

    expect(find.text('Diagnostic logging'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('player-menu-log-neat')));
    expect(picked, LogLevel.neat);
  });

  testWidgets('tapping "Export logs…" fires onExportLogs', (tester) async {
    var exported = false;
    await tester.pumpWidget(
      _host(_button(onExportLogs: () => exported = true)),
    );
    await _openSettings(tester);

    await _tap(tester, find.byKey(const Key('player-menu-export-logs')));
    expect(exported, isTrue);
  });

  testWidgets('dim slider reset restores the default opacity', (tester) async {
    double? changed;
    await tester.pumpWidget(
      _host(
        _button(chatIdleDim: 0.9, onChatIdleDimChanged: (v) => changed = v),
      ),
    );
    await _openSettings(tester);

    expect(find.text('Dimmed chat readability'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget); // starts at the passed value

    await _tap(tester, find.byKey(const Key('player-menu-dim-reset')));
    // Default is kChatIdleGhostOpacity (0.5) → 50%.
    expect(changed, 0.5);
    expect(find.text('50%'), findsOneWidget);
  });
}
