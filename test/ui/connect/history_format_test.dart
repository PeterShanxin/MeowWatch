import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/ui/connect/history_format.dart';

HistoryEntry entry({
  int? durationMs,
  int lastPositionMs = 0,
  DateTime? playedAt,
  int fileSizeBytes = 0,
}) =>
    HistoryEntry(
      id: 1,
      filePath: '/x.mkv',
      fileName: 'x.mkv',
      fileSizeBytes: fileSizeBytes,
      durationMs: durationMs,
      lastPositionMs: lastPositionMs,
      playedAt: playedAt ?? DateTime(2026, 5, 30),
    );

void main() {
  group('formatRuntime', () {
    test('m:ss under an hour', () {
      expect(formatRuntime(0), '0:00');
      expect(formatRuntime(65 * 1000), '1:05');
      expect(formatRuntime(47 * 60 * 1000 + 32 * 1000), '47:32');
    });

    test('h:mm:ss at or above an hour', () {
      expect(formatRuntime(3600 * 1000), '1:00:00');
      expect(formatRuntime((1 * 3600 + 45 * 60) * 1000), '1:45:00');
    });

    test('clamps negatives to zero', () {
      expect(formatRuntime(-500), '0:00');
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 5, 30, 12, 0, 0);
    test('buckets', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 10)), now),
          'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now),
          '5m ago');
      expect(
          relativeTime(now.subtract(const Duration(hours: 3)), now), '3h ago');
      expect(relativeTime(now.subtract(const Duration(days: 1)), now),
          'yesterday');
      expect(relativeTime(now.subtract(const Duration(days: 3)), now),
          '3 days ago');
      expect(relativeTime(now.subtract(const Duration(days: 14)), now),
          '2 weeks ago');
      expect(relativeTime(now.subtract(const Duration(days: 60)), now),
          '2 months ago');
    });
  });

  group('progressFraction', () {
    test('null when duration unknown or zero', () {
      expect(progressFraction(entry(durationMs: null)), isNull);
      expect(progressFraction(entry(durationMs: 0)), isNull);
    });
    test('ratio, clamped', () {
      expect(progressFraction(entry(durationMs: 1000, lastPositionMs: 250)),
          0.25);
      expect(
          progressFraction(entry(durationMs: 1000, lastPositionMs: 5000)), 1.0);
    });
  });

  group('formatFileSize', () {
    test('empty when unknown', () => expect(formatFileSize(0), ''));
    test('KB / MB / GB buckets', () {
      expect(formatFileSize(512 * 1024), '512 KB');
      expect(formatFileSize(720 * 1024 * 1024), '720 MB');
      expect(
          formatFileSize((1.4 * 1024 * 1024 * 1024).round()), '1.4 GB');
    });
  });

  group('historySubtitle', () {
    final now = DateTime(2026, 5, 30, 12, 0, 0);
    test('full line with percent when duration known', () {
      final e = entry(
        durationMs: (1 * 3600 + 45 * 60) * 1000,
        lastPositionMs: 47 * 60 * 1000 + 32 * 1000,
        playedAt: now.subtract(const Duration(days: 2)),
      );
      expect(historySubtitle(e, now), '47:32 / 1:45:00 · 45% · 2 days ago');
    });

    test('appends file size when known', () {
      final e = entry(
        durationMs: (1 * 3600 + 45 * 60) * 1000,
        lastPositionMs: 47 * 60 * 1000 + 32 * 1000,
        playedAt: now.subtract(const Duration(days: 2)),
        fileSizeBytes: 720 * 1024 * 1024,
      );
      expect(historySubtitle(e, now),
          '47:32 / 1:45:00 · 45% · 2 days ago · 720 MB');
    });

    test('just the played label when duration unknown', () {
      final e = entry(
          durationMs: null, playedAt: now.subtract(const Duration(hours: 2)));
      expect(historySubtitle(e, now), '2h ago');
    });
  });
}
