import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/history_collapse.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/history_mode.dart';

HistoryEntry _e(int id, {String? room}) => HistoryEntry(
      id: id,
      filePath: 'p$id',
      fileName: 'f$id',
      fileSizeBytes: 1,
      durationMs: null,
      lastPositionMs: 0,
      // playedAt only matters for ordering, which the input already encodes.
      playedAt: DateTime.fromMillisecondsSinceEpoch(id),
      room: room,
    );

void main() {
  // Newest-first input, as watchRecent emits.
  final newestFirst = <HistoryEntry>[
    _e(5, room: 'cozy'), // latest in cozy
    _e(4, room: 'cozy'),
    _e(3, room: 'breezy'), // latest in breezy
    _e(2), // solo (no room)
    _e(1, room: 'cozy'),
  ];

  test('everyVideo is identity (same order, same items)', () {
    final out = collapseHistory(newestFirst, HistoryMode.everyVideo);
    expect(out.map((e) => e.id).toList(), [5, 4, 3, 2, 1]);
  });

  test('latestPerRoom keeps newest per room and all room-less entries', () {
    final out = collapseHistory(newestFirst, HistoryMode.latestPerRoom);
    // cozy collapses to id 5; breezy stays at 3; solo id 2 always kept.
    expect(out.map((e) => e.id).toList(), [5, 3, 2]);
  });

  test('latestPerRoom keeps every room-less entry (empty string == no room)', () {
    final input = <HistoryEntry>[_e(3, room: ''), _e(2), _e(1, room: 'r')];
    final out = collapseHistory(input, HistoryMode.latestPerRoom);
    expect(out.map((e) => e.id).toList(), [3, 2, 1]);
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
    // Mutating the returned list must not reach back into the caller's input.
    out.clear();
    expect(input, hasLength(2));
  });
}
