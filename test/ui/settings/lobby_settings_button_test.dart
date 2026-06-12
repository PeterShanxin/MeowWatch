import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/audio/notify_sounds.dart';
import 'package:meowwatch/core/debug/log_level.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/settings/lobby_settings_button.dart';

Widget _host(Widget child) => MaterialApp(
  theme: themeDataFor(MeowThemeId.cozy),
  home: Scaffold(body: child),
);

LobbySettingsButton _button({
  ValueChanged<MeowThemeId>? onThemeChanged,
  LogLevel logLevel = LogLevel.verbose,
  ValueChanged<LogLevel>? onLogLevelChanged,
  VoidCallback? onExportLogs,
}) => LobbySettingsButton(
  currentTheme: MeowThemeId.cozy,
  onThemeChanged: onThemeChanged ?? (_) {},
  primarySoundId: kDefaultPrimarySoundId,
  onPrimarySoundChanged: (_) {},
  secondarySoundId: kDefaultSecondarySoundId,
  onSecondarySoundChanged: (_) {},
  onPreviewSound: (_) {},
  logLevel: logLevel,
  onLogLevelChanged: onLogLevelChanged ?? (_) {},
  onExportLogs: onExportLogs ?? () {},
);

/// Open the lobby gear. The popover can be taller than the default 600px test
/// viewport, so size the window up first and let later taps scroll into view.
Future<void> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.tap(find.byKey(const Key('lobby-settings-gear')));
  await tester.pumpAndSettle();
}

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

    await tester.tap(find.byKey(const Key('lobby-settings-gear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-swatch-noir')), findsOneWidget);
  });

  testWidgets('shows settings only — no room rows', (tester) async {
    await tester.pumpWidget(_host(_button()));
    await _open(tester);

    // The settings the lobby exposes.
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Diagnostic logging'), findsOneWidget);
    expect(find.byKey(const Key('primary-sound-picker')), findsOneWidget);
    expect(find.byKey(const Key('player-menu-export-logs')), findsOneWidget);

    // None of the in-room-only rows.
    expect(find.byKey(const Key('player-menu-leave')), findsNothing);
    expect(find.byKey(const Key('player-menu-room-code')), findsNothing);
    expect(find.byKey(const Key('player-menu-load')), findsNothing);
  });

  testWidgets('tapping a swatch fires onThemeChanged', (tester) async {
    MeowThemeId? picked;
    await tester.pumpWidget(
      _host(_button(onThemeChanged: (id) => picked = id)),
    );
    await _open(tester);
    await _tap(tester, find.byKey(const Key('theme-swatch-aurora')));
    expect(picked, MeowThemeId.aurora);
  });

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
    await _open(tester);
    await _tap(tester, find.byKey(const Key('player-menu-log-neat')));
    expect(picked, LogLevel.neat);
  });

  testWidgets('tapping "Export logs…" fires onExportLogs', (tester) async {
    var exported = false;
    await tester.pumpWidget(
      _host(_button(onExportLogs: () => exported = true)),
    );
    await _open(tester);
    await _tap(tester, find.byKey(const Key('player-menu-export-logs')));
    expect(exported, isTrue);
  });
}
