import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/history_collapse.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/history_mode.dart';
import 'package:meowwatch/core/data/watch_context.dart';

HistoryEntry _e(int id, {String? room}) {
  final ctx = (room != null && room.isNotEmpty)
      ? WatchContext.synced(server: 's', port: 8999, room: room)
      : const WatchContext.local();
  return HistoryEntry(
    id: id,
    filePath: 'p$id',
    fileName: 'f$id',
    fileSizeBytes: 1,
    durationMs: null,
    lastPositionMs: 0,
    playedAt: DateTime.fromMillisecondsSinceEpoch(id),
    contextKey: ctx.key,
    room: ctx.storedRoom,
    server: ctx.storedServer,
    port: ctx.storedPort,
  );
}

void main() {
  final newestFirst = <HistoryEntry>[
    _e(5, room: 'cozy'),
    _e(4, room: 'cozy'),
    _e(3, room: 'breezy'),
    _e(2),
    _e(1, room: 'cozy'),
  ];

  test('everyVideo is identity (same order, same items)', () {
    final out = collapseHistory(newestFirst, HistoryMode.everyVideo);
    expect(out.map((e) => e.id).toList(), [5, 4, 3, 2, 1]);
  });

  test('latestPerRoom keeps newest per context key', () {
    final out = collapseHistory(newestFirst, HistoryMode.latestPerRoom);
    expect(out.map((e) => e.id).toList(), [5, 3, 2]);
  });

  test('latestPerRoom collapses Local to one newest bucket', () {
    final input = <HistoryEntry>[_e(3), _e(2), _e(1, room: 'r')];
    final out = collapseHistory(input, HistoryMode.latestPerRoom);
    expect(out.map((e) => e.id).toList(), [3, 1]);
  });

  test('latestPerRoom keeps Local and room A of the same media', () {
    final local = HistoryEntry(
      id: 2,
      filePath: 'A',
      fileName: 'A',
      fileSizeBytes: 1,
      durationMs: null,
      lastPositionMs: 1,
      playedAt: DateTime.fromMillisecondsSinceEpoch(2),
      contextKey: kLocalWatchContextKey,
    );
    final synced = HistoryEntry(
      id: 1,
      filePath: 'A',
      fileName: 'A',
      fileSizeBytes: 1,
      durationMs: null,
      lastPositionMs: 2,
      playedAt: DateTime.fromMillisecondsSinceEpoch(1),
      contextKey: syncedWatchContextKey(
        server: 's',
        port: 8999,
        room: 'room-a',
      ),
      room: 'room-a',
      server: 's',
      port: 8999,
    );
    final out = collapseHistory([local, synced], HistoryMode.latestPerRoom);
    expect(out.map((e) => e.id).toList(), [2, 1]);
  });

  test('does not mutate the input list', () {
    final input = <HistoryEntry>[_e(2, room: 'r'), _e(1, room: 'r')];
    collapseHistory(input, HistoryMode.latestPerRoom);
    expect(input.map((e) => e.id).toList(), [2, 1]);
  });

  test('everyVideo returns a copy that does not alias the input', () {
    final input = <HistoryEntry>[_e(1), _e(2)];
    final out = collapseHistory(input, HistoryMode.everyVideo);
    expect(identical(out, input), isFalse);
    out.clear();
    expect(input, hasLength(2));
  });
}
