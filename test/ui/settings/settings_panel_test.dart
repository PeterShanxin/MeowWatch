import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/audio/notify_sounds.dart';
import 'package:meowwatch/core/data/history_mode.dart';
import 'package:meowwatch/core/data/settings_store.dart';
import 'package:meowwatch/core/debug/log_level.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/settings/settings_panel.dart';

Widget _host(Widget child) => MaterialApp(
  theme: themeDataFor(MeowThemeId.cozy),
  home: Scaffold(body: child),
);

SettingsPanel _panel({
  HistoryMode historyMode = HistoryMode.latestPerRoom,
  ValueChanged<HistoryMode>? onHistoryModeChanged,
  String primarySoundId = kDefaultPrimarySoundId,
  ValueChanged<String>? onPrimarySoundChanged,
  String secondarySoundId = kDefaultSecondarySoundId,
  ValueChanged<String>? onSecondarySoundChanged,
  ValueChanged<String>? onPreviewSound,
  LogLevel logLevel = LogLevel.verbose,
  ValueChanged<LogLevel>? onLogLevelChanged,
  VoidCallback? onExportLogs,
}) => SettingsPanel(
  historyMode: historyMode,
  onHistoryModeChanged: onHistoryModeChanged ?? (_) {},
  primarySoundId: primarySoundId,
  onPrimarySoundChanged: onPrimarySoundChanged ?? (_) {},
  secondarySoundId: secondarySoundId,
  onSecondarySoundChanged: onSecondarySoundChanged ?? (_) {},
  onPreviewSound: onPreviewSound ?? (_) {},
  logLevel: logLevel,
  onLogLevelChanged: onLogLevelChanged ?? (_) {},
  onExportLogs: onExportLogs ?? () {},
);

void main() {
  testWidgets('renders the sound pickers and the diagnostic-log control', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_panel()));
    expect(find.byKey(const Key('primary-sound-picker')), findsOneWidget);
    expect(find.byKey(const Key('secondary-sound-picker')), findsOneWidget);
    expect(find.text('Diagnostic logging'), findsOneWidget);
  });

  testWidgets('picking a log level fires onLogLevelChanged', (tester) async {
    LogLevel? picked;
    await tester.pumpWidget(
      _host(_panel(onLogLevelChanged: (v) => picked = v)),
    );
    await tester.tap(find.byKey(const Key('player-menu-log-neat')));
    expect(picked, LogLevel.neat);
  });

  testWidgets('tapping "Export logs…" fires onExportLogs', (tester) async {
    var exported = false;
    await tester.pumpWidget(_host(_panel(onExportLogs: () => exported = true)));
    await tester.tap(find.byKey(const Key('player-menu-export-logs')));
    expect(exported, isTrue);
  });

  testWidgets('renders the Continue watching toggle', (tester) async {
    await tester.pumpWidget(_host(_panel()));
    expect(find.text('Continue watching'), findsOneWidget);
    expect(
      find.byKey(Key('history-mode-${HistoryMode.latestPerRoom.storageName}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('history-mode-${HistoryMode.everyVideo.storageName}')),
      findsOneWidget,
    );
  });

  testWidgets('picking Every video fires onHistoryModeChanged', (tester) async {
    HistoryMode? picked;
    await tester.pumpWidget(
      _host(_panel(onHistoryModeChanged: (v) => picked = v)),
    );
    await tester
        .tap(find.byKey(Key('history-mode-${HistoryMode.everyVideo.storageName}')));
    expect(picked, HistoryMode.everyVideo);
  });

  test('kHistoryModeSettingKey is stable', () {
    expect(kHistoryModeSettingKey, 'history_mode');
  });
}
