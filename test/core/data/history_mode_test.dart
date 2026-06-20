import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/history_mode.dart';

void main() {
  test('storageName round-trips through historyModeFromName', () {
    for (final mode in HistoryMode.values) {
      expect(historyModeFromName(mode.storageName), mode);
    }
  });

  test('storageName values are stable snake_case', () {
    expect(HistoryMode.latestPerRoom.storageName, 'latest_per_room');
    expect(HistoryMode.everyVideo.storageName, 'every_video');
  });

  test('absent or unknown name falls back to latestPerRoom', () {
    expect(historyModeFromName(null), HistoryMode.latestPerRoom);
    expect(historyModeFromName(''), HistoryMode.latestPerRoom);
    expect(historyModeFromName('garbage'), HistoryMode.latestPerRoom);
  });
}
