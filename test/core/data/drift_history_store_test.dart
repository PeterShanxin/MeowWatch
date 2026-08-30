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
    final playedAt = single.playedAt;

    // Re-opening outside a room must not wipe the recorded room endpoint/name,
    // and must not bump playedAt (that would make Latest-per-room look like
    // the old room just watched this file — #252 / #253).
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(
        filePath: r'D:\v\ep1.mkv', fileName: 'ep1.mkv', fileSizeBytes: 1);
    single = (await store.watchRecent().first).single;
    expect(single.room, 'breezy-crow-66');
    expect(single.username, 'meow');
    expect(single.server, 'syncplay.pl');
    expect(single.port, 8995);
    expect(single.playedAt, playedAt);
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

  test('latestPerRoom keeps the full-scan contract across a large history',
      () async {
    // Perf work (#199) must not change the store contract: every distinct
    // room's latest entry stays reachable however large the table grows. The
    // SQL collapses per-room before rows ever reach Dart, so only `limit`
    // rows are materialized per invalidation — but the *result* matches the
    // original full scan exactly.
    for (var i = 0; i < 205; i++) {
      // playedAt ties at whole-second resolution; id desc breaks the tie, so
      // later inserts are unambiguously newer without needing delays.
      await store.recordOpen(
          filePath: 'f$i', fileName: 'f$i', fileSizeBytes: 1, room: 'room$i');
    }

    // Every distinct room is reachable — no truncation before the collapse.
    final all = await store
        .watchRecent(limit: 300, mode: HistoryMode.latestPerRoom)
        .first;
    expect(all, hasLength(205));
    expect(all.first.fileName, 'f204');
    expect(all.last.fileName, 'f0');

    // The realistic small-limit path: newest rooms, newest first.
    final recent =
        await store.watchRecent(mode: HistoryMode.latestPerRoom).first;
    expect(
      recent.map((e) => e.fileName).toList(),
      List.generate(6, (i) => 'f${204 - i}'),
    );
  });

  test(
      'latestPerRoom surfaces older distinct rooms when one room dominates '
      'recent history (PR #216 review)', () async {
    // Older distinct rooms + a solo watch…
    for (var i = 0; i < 4; i++) {
      await store.recordOpen(
          filePath: 'old$i',
          fileName: 'old$i',
          fileSizeBytes: 1,
          room: 'oldroom$i');
    }
    await store.recordOpen(
        filePath: 'solo', fileName: 'solo', fileSizeBytes: 1);
    // …then a flood of newer entries ALL in one room. A cap that truncates
    // the scan before collapsing would only ever see this room and shrink
    // Continue Watching to a single card.
    for (var i = 0; i < 210; i++) {
      await store.recordOpen(
          filePath: 'flood$i',
          fileName: 'flood$i',
          fileSizeBytes: 1,
          room: 'hot');
    }

    final list =
        await store.watchRecent(mode: HistoryMode.latestPerRoom).first;
    expect(
      list.map((e) => e.fileName).toList(),
      ['flood209', 'solo', 'old3', 'old2', 'old1', 'old0'],
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

  test(
      'latestPerRoom merges exotic-whitespace-padded room aliases before '
      'limiting (PR #216 review)', () async {
    // A pasted share code can drag a tab or NBSP into the room name. Dart's
    // trim() strips those, so collapseHistory treats "cozy", "\tcozy\t" and
    // NBSP-padded "cozy" as ONE room — the SQL grouping key must agree, or
    // the LIMIT eats slots on aliases and the post-pass can't pull in the
    // next older distinct room (under-filled Continue Watching).
    for (var i = 0; i < 5; i++) {
      await store.recordOpen(
          filePath: 'old$i',
          fileName: 'old$i',
          fileSizeBytes: 1,
          room: 'oldroom$i');
    }
    await store.recordOpen(
        filePath: 'clean', fileName: 'clean', fileSizeBytes: 1, room: 'cozy');
    await store.recordOpen(
        filePath: 'tabbed',
        fileName: 'tabbed',
        fileSizeBytes: 1,
        room: '\tcozy\t');
    await store.recordOpen(
        filePath: 'nbsp',
        fileName: 'nbsp',
        fileSizeBytes: 1,
        room: '\u00A0cozy\u00A0');

    final list =
        await store.watchRecent(mode: HistoryMode.latestPerRoom).first;
    // One card for the cozy trio (its newest entry), then every older room.
    expect(
      list.map((e) => e.fileName).toList(),
      ['nbsp', 'old4', 'old3', 'old2', 'old1', 'old0'],
    );
  });

  test(
      'a room of pure exotic whitespace counts as roomless — every entry kept '
      '(PR #216 review)', () async {
    // Dart trim() reduces a pure-NBSP room to '', i.e. "not in a room", and
    // roomless entries are never collapsed. The SQL room_key must agree.
    await store.recordOpen(
        filePath: 'g1', fileName: 'g1', fileSizeBytes: 1, room: '\u00A0');
    await store.recordOpen(
        filePath: 'g2', fileName: 'g2', fileSizeBytes: 1, room: '\u00A0');

    final list =
        await store.watchRecent(mode: HistoryMode.latestPerRoom).first;
    expect(list.map((e) => e.fileName).toList(), ['g2', 'g1']);
  });

  test('kDartTrimWhitespace matches String.trim exactly across the BMP', () {
    // The SQL TRIM(x, kDartTrimWhitespace) key is only correct if the char
    // set is EXACTLY what Dart's String.trim() strips. Sweep every BMP code
    // point and compare against the running SDK — if a Dart release ever
    // shifts its whitespace set, this fails loudly instead of silently
    // splitting room groups.
    final set = kDartTrimWhitespace.codeUnits.toSet();
    final mismatches = <String>[];
    for (var c = 0; c <= 0xFFFF; c++) {
      if (c >= 0xD800 && c <= 0xDFFF) continue; // lone surrogates
      final dartTrims = String.fromCharCode(c).trim().isEmpty;
      if (dartTrims != set.contains(c)) {
        mismatches.add(
            'U+${c.toRadixString(16).padLeft(4, '0').toUpperCase()} '
            'dart:$dartTrims set:${set.contains(c)}');
      }
    }
    expect(mismatches, isEmpty);
  });
}
