import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/history_entry.dart';

void main() {
  final played = DateTime(2026, 5, 29, 13);
  final base = HistoryEntry(
    id: 1,
    filePath: r'D:\videos\ep1.mkv',
    fileName: 'ep1.mkv',
    fileSizeBytes: 1024,
    durationMs: 600000,
    lastPositionMs: 12000,
    playedAt: played,
    server: 'syncplay.pl',
    port: 8995,
  );

  test('value equality', () {
    expect(
      base,
      HistoryEntry(
        id: 1,
        filePath: r'D:\videos\ep1.mkv',
        fileName: 'ep1.mkv',
        fileSizeBytes: 1024,
        durationMs: 600000,
        lastPositionMs: 12000,
        playedAt: played,
        server: 'syncplay.pl',
        port: 8995,
      ),
    );
  });

  test('copyWith updates position', () {
    expect(base.copyWith(lastPositionMs: 30000).lastPositionMs, 30000);
    expect(base.copyWith(lastPositionMs: 30000).fileName, base.fileName);
    expect(base.copyWith(port: 9000).port, 9000);
  });
}
