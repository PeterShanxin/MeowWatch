import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/drift_stores.dart';
import 'package:meowwatch/core/data/history_mode.dart';

void main() {
  late AppDatabase db;
  late DriftHistoryStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftHistoryStore(db);
  });

  tearDown(() async => db.close());

  test('recordOpen inserts a history entry', () async {
    await store.recordOpen(
      filePath: r'D:\v\ep1.mkv',
      fileName: 'ep1.mkv',
      fileSizeBytes: 2048,
      durationMs: 600000,
    );
    final list = await store.watchRecent().first;
    expect(list, hasLength(1));
    expect(list.single.fileName, 'ep1.mkv');
    expect(list.single.lastPositionMs, 0);
  });

  test('recordOpen persists room endpoint + username; later solo open keeps them',
      () async {
    await store.recordOpen(
      filePath: r'D:\v\ep1.mkv',
      fileName: 'ep1.mkv',
      fileSizeBytes: 1,
      room: 'breezy-crow-66',
      username: 'meow',
      server: 'syncplay.pl',
      port: 8995,
    );
    var single = (await store.watchRecent().first).single;
    expect(single.room, 'breezy-crow-66');
    expect(single.username, 'meow');
    expect(single.server, 'syncplay.pl');
    expect(single.port, 8995);

    // Re-opening outside a room must not wipe the recorded room endpoint/name.
    await store.recordOpen(
        filePath: r'D:\v\ep1.mkv', fileName: 'ep1.mkv', fileSizeBytes: 1);
    single = (await store.watchRecent().first).single;
    expect(single.room, 'breezy-crow-66');
    expect(single.username, 'meow');
    expect(single.server, 'syncplay.pl');
    expect(single.port, 8995);
  });

  test('recordOpen on the same path keeps last position, refreshes playedAt',
      () async {
    await store.recordOpen(
        filePath: r'D:\v\ep1.mkv', fileName: 'ep1.mkv', fileSizeBytes: 1);
    await store.updatePosition(filePath: r'D:\v\ep1.mkv', positionMs: 42000);
    await store.recordOpen(
        filePath: r'D:\v\ep1.mkv', fileName: 'ep1.mkv', fileSizeBytes: 1);
    final list = await store.watchRecent().first;
    expect(list, hasLength(1));
    expect(list.single.lastPositionMs, 42000);
  });

  test('updatePosition backfills duration but never clobbers it with 0',
      () async {
    // Opened before mpv knew the runtime → duration 0.
    await store.recordOpen(
        filePath: 'a', fileName: 'a', fileSizeBytes: 1, durationMs: 0);
    // Later tick once the runtime is known fills it in.
    await store.updatePosition(
        filePath: 'a', positionMs: 1000, durationMs: 600000);
    var single = (await store.watchRecent().first).single;
    expect(single.durationMs, 600000);
    // A subsequent 0 (e.g. a reload frame) must not wipe the known runtime.
    await store.updatePosition(filePath: 'a', positionMs: 2000, durationMs: 0);
    single = (await store.watchRecent().first).single;
    expect(single.durationMs, 600000);
  });

  test('recordOpen never clobbers a known duration with 0 (#208 review)',
      () async {
    await store.recordOpen(
        filePath: 'a', fileName: 'a', fileSizeBytes: 1, durationMs: 0);
    // A periodic tick backfilled the real runtime while recordOpen's slow
    // file-stat was still in flight…
    await store.updatePosition(
        filePath: 'a', positionMs: 1000, durationMs: 600000);
    // …then a re-open commits with the duration captured at open time (0).
    // The known runtime must survive, like updatePosition's own guard.
    await store.recordOpen(
        filePath: 'a', fileName: 'a', fileSizeBytes: 1, durationMs: 0);
    final single = (await store.watchRecent().first).single;
    expect(single.durationMs, 600000);
  });

  test('updatePosition on an unknown path is a no-op and reports it', () async {
    // False lets ResumeSaveGate know nothing was persisted, so the periodic
    // save retries instead of baselining a silent no-op (#208 review).
    expect(
      await store.updatePosition(filePath: r'D:\nope.mkv', positionMs: 100),
      isFalse,
    );
    expect(await store.watchRecent().first, isEmpty);

    await store.recordOpen(
        filePath: r'D:\nope.mkv', fileName: 'nope.mkv', fileSizeBytes: 1);
    expect(
      await store.updatePosition(filePath: r'D:\nope.mkv', positionMs: 100),
      isTrue,
    );
  });

  test('watchRecent orders newest first and honors limit', () async {
    await store.recordOpen(filePath: 'a', fileName: 'a', fileSizeBytes: 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(filePath: 'b', fileName: 'b', fileSizeBytes: 1);
    final list = await store.watchRecent(limit: 1).first;
    expect(list.map((e) => e.fileName).toList(), ['b']);
  });

  test('delete removes a single entry', () async {
    await store.recordOpen(filePath: 'a', fileName: 'a', fileSizeBytes: 1);
    await store.recordOpen(filePath: 'b', fileName: 'b', fileSizeBytes: 1);
    final before = await store.watchRecent().first;
    final idA = before.firstWhere((e) => e.fileName == 'a').id;

    await store.delete(idA);

    final after = await store.watchRecent().first;
    expect(after.map((e) => e.fileName).toList(), ['b']);
  });

  test('clearAll empties the history', () async {
    await store.recordOpen(filePath: 'a', fileName: 'a', fileSizeBytes: 1);
    await store.recordOpen(filePath: 'b', fileName: 'b', fileSizeBytes: 1);

    await store.clearAll();

    expect(await store.watchRecent().first, isEmpty);
  });

  test('latestPerRoom hides older same-room entries but keeps the rows',
      () async {
    await store.recordOpen(
        filePath: 'a', fileName: 'a', fileSizeBytes: 1, room: 'cozy');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(
        filePath: 'b', fileName: 'b', fileSizeBytes: 1, room: 'cozy');

    final collapsed =
        await store.watchRecent(mode: HistoryMode.latestPerRoom).first;
    expect(collapsed.map((e) => e.fileName).toList(), ['b']);

    // Hide-not-delete: everyVideo still sees both rows (nothing was removed).
    final all = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(all.map((e) => e.fileName).toList(), ['b', 'a']);
  });

  test('latestPerRoom scan is SQL-bounded: rows beyond the cap stay unread',
      () async {
    // Perf guard (#199): latestPerRoom used to read the WHOLE table on every
    // invalidation. The query now carries a generous SQL cap applied before
    // the collapse, so history growth can't turn each watch emission into a
    // full-table scan.
    final cap = DriftHistoryStore.latestPerRoomScanCap;
    for (var i = 0; i < cap + 5; i++) {
      // Distinct rooms so nothing collapses — every scanned row survives,
      // making the result length a direct probe of the SQL scan bound.
      // playedAt ties at whole-second resolution; id desc breaks the tie, so
      // later inserts are unambiguously newer without needing delays.
      await store.recordOpen(
          filePath: 'f$i', fileName: 'f$i', fileSizeBytes: 1, room: 'room$i');
    }

    final unbounded = await store
        .watchRecent(limit: cap + 5, mode: HistoryMode.latestPerRoom)
        .first;
    // Only the newest `cap` rows were scanned — the 5 oldest never left SQL.
    expect(unbounded, hasLength(cap));
    expect(unbounded.first.fileName, 'f${cap + 4}');
    expect(unbounded.last.fileName, 'f5');

    // The realistic small-limit path is untouched: newest rooms, newest first.
    final recent =
        await store.watchRecent(mode: HistoryMode.latestPerRoom).first;
    expect(
      recent.map((e) => e.fileName).toList(),
      List.generate(6, (i) => 'f${cap + 4 - i}'),
    );
  });

  test('latestPerRoom keeps room-less entries and fills limit after collapse',
      () async {
    // cozy x2 (collapses to 1) + two solo files → limit:2 should yield 2 rows.
    await store.recordOpen(
        filePath: 'a', fileName: 'a', fileSizeBytes: 1, room: 'cozy');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(filePath: 'b', fileName: 'b', fileSizeBytes: 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(
        filePath: 'c', fileName: 'c', fileSizeBytes: 1, room: 'cozy');

    final list =
        await store.watchRecent(limit: 2, mode: HistoryMode.latestPerRoom).first;
    // newest-first c(cozy), b(solo), a(cozy→hidden) → collapse → [c, b] → take 2.
    expect(list.map((e) => e.fileName).toList(), ['c', 'b']);
  });
}
