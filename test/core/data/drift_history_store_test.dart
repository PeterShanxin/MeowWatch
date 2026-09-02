import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/drift_stores.dart';
import 'package:meowwatch/core/data/history_mode.dart';
import 'package:meowwatch/core/data/watch_context.dart';

void main() {
  late AppDatabase db;
  late DriftHistoryStore store;

  const local = WatchContext.local();
  final roomA = WatchContext.synced(
    server: 'syncplay.pl',
    port: 8999,
    room: 'bouncy-snail-picks-spry-carrot',
  );
  final roomB = WatchContext.synced(
    server: 'syncplay.pl',
    port: 8999,
    room: 'mellow-robin-wears-wise-pickle',
  );

  Future<void> open(
    String path, {
    WatchContext context = local,
    String? name,
    String? username,
    int? durationMs,
  }) {
    return store.recordOpen(
      filePath: path,
      fileName: name ?? path,
      fileSizeBytes: 1,
      context: context,
      username: username,
      durationMs: durationMs,
    );
  }

  Future<bool> seek(
    String path, {
    required int positionMs,
    WatchContext context = local,
    int? durationMs,
  }) {
    return store.updatePosition(
      filePath: path,
      context: context,
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }

  setUp(() {
    db = AppDatabase.memory();
    store = DriftHistoryStore(db);
  });

  tearDown(() async => db.close());

  test('recordOpen inserts a history entry', () async {
    await open(r'D:\v\ep1.mkv', name: 'ep1.mkv', durationMs: 600000);
    final list = await store.watchRecent().first;
    expect(list, hasLength(1));
    expect(list.single.fileName, 'ep1.mkv');
    expect(list.single.lastPositionMs, 0);
    expect(list.single.isLocalContext, isTrue);
  });

  test('Local context with a room uses that stable room key', () async {
    const localRoom = WatchContext.local(
      server: 'syncplay.pl',
      port: 8999,
      room: 'quiet-otter-counts-stars',
    );
    await open(r'D:\v\ep1.mkv', context: localRoom, username: 'meow');

    final entry = (await store.watchRecent().first).single;
    expect(
      entry.contextKey,
      'synced|syncplay.pl|8999|quiet-otter-counts-stars',
    );
    expect(entry.room, 'quiet-otter-counts-stars');
    expect(entry.server, 'syncplay.pl');
    expect(entry.port, 8999);
  });

  test('Local toggle updates the existing same-room row', () async {
    const path = r'D:\v\A.mkv';
    const localRoom = WatchContext.local(
      server: 'syncplay.pl',
      port: 8999,
      room: 'bouncy-snail-picks-spry-carrot',
    );

    await open(path, context: roomA, username: 'meow');
    await seek(path, context: roomA, positionMs: 109958);
    await open(path, context: localRoom, username: 'meow');
    await seek(path, context: localRoom, positionMs: 124875);

    final all = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(all, hasLength(1));
    expect(all.single.contextKey, roomA.key);
    expect(all.single.lastPositionMs, 124875);
    expect(all.single.room, roomA.room);
  });

  test('same media Local + room A coexist with independent progress', () async {
    const path = r'D:\v\A.mkv';
    await open(path, name: 'A.mkv', context: roomA, username: 'meow');
    await seek(path, context: roomA, positionMs: 28 * 60 * 1000 + 8000);

    await open(path, name: 'A.mkv', context: local);
    await seek(path, context: local, positionMs: 35 * 60 * 1000 + 42000);

    final all = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(all, hasLength(2));
    final synced = all.firstWhere((e) => !e.isLocalContext);
    final solo = all.firstWhere((e) => e.isLocalContext);
    expect(synced.lastPositionMs, 28 * 60 * 1000 + 8000);
    expect(synced.room, 'bouncy-snail-picks-spry-carrot');
    expect(synced.username, 'meow');
    expect(synced.server, 'syncplay.pl');
    expect(synced.port, 8999);
    expect(solo.lastPositionMs, 35 * 60 * 1000 + 42000);
    expect(solo.room, isNull);
    expect(solo.contextKey, kLocalWatchContextKey);
  });

  test('same media room A + room B are separate records', () async {
    const path = r'D:\v\A.mkv';
    await open(path, name: 'A.mkv', context: roomA);
    await seek(path, context: roomA, positionMs: 1000);
    await open(path, name: 'A.mkv', context: roomB);
    await seek(path, context: roomB, positionMs: 2000);

    final all = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(all, hasLength(2));
    expect(all.firstWhere((e) => e.room == roomA.room).lastPositionMs, 1000);
    expect(all.firstWhere((e) => e.room == roomB.room).lastPositionMs, 2000);
  });

  test('local rewatch only changes Local progress', () async {
    const path = r'D:\v\A.mkv';
    await open(path, context: roomA);
    await seek(path, context: roomA, positionMs: 1111);
    await open(path, context: local);
    await seek(path, context: local, positionMs: 2222);
    await seek(path, context: local, positionMs: 3333);

    final all = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(all.firstWhere((e) => e.isLocalContext).lastPositionMs, 3333);
    expect(all.firstWhere((e) => !e.isLocalContext).lastPositionMs, 1111);
  });

  test('synced rewatch only changes that room progress', () async {
    const path = r'D:\v\A.mkv';
    await open(path, context: local);
    await seek(path, context: local, positionMs: 1111);
    await open(path, context: roomA);
    await seek(path, context: roomA, positionMs: 2222);
    await seek(path, context: roomA, positionMs: 4444);

    final all = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(all.firstWhere((e) => e.isLocalContext).lastPositionMs, 1111);
    expect(all.firstWhere((e) => !e.isLocalContext).lastPositionMs, 4444);
  });

  test(
    'recordOpen on the same context keeps last position, refreshes playedAt',
    () async {
      await open(r'D:\v\ep1.mkv', name: 'ep1.mkv');
      await seek(r'D:\v\ep1.mkv', positionMs: 42000);
      await open(r'D:\v\ep1.mkv', name: 'ep1.mkv');
      final list = await store.watchRecent().first;
      expect(list, hasLength(1));
      expect(list.single.lastPositionMs, 42000);
    },
  );

  test(
    'updatePosition backfills duration but never clobbers it with 0',
    () async {
      await open('a', durationMs: 0);
      await seek('a', positionMs: 1000, durationMs: 600000);
      var single = (await store.watchRecent().first).single;
      expect(single.durationMs, 600000);
      await seek('a', positionMs: 2000, durationMs: 0);
      single = (await store.watchRecent().first).single;
      expect(single.durationMs, 600000);
    },
  );

  test(
    'recordOpen never clobbers a known duration with 0 (#208 review)',
    () async {
      await open('a', durationMs: 0);
      await seek('a', positionMs: 1000, durationMs: 600000);
      await open('a', durationMs: 0);
      final single = (await store.watchRecent().first).single;
      expect(single.durationMs, 600000);
    },
  );

  test('updatePosition on an unknown path is a no-op and reports it', () async {
    expect(await seek(r'D:\nope.mkv', positionMs: 100), isFalse);
    expect(await store.watchRecent().first, isEmpty);

    await open(r'D:\nope.mkv', name: 'nope.mkv');
    expect(await seek(r'D:\nope.mkv', positionMs: 100), isTrue);
  });

  test('watchRecent orders newest first and honors limit', () async {
    await open('a');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await open('b');
    final list = await store.watchRecent(limit: 1).first;
    expect(list.map((e) => e.fileName).toList(), ['b']);
  });

  test('delete removes a single entry', () async {
    await open('a');
    await open('b');
    final before = await store.watchRecent().first;
    final idA = before.firstWhere((e) => e.fileName == 'a').id;

    await store.delete(idA);

    final after = await store.watchRecent().first;
    expect(after.map((e) => e.fileName).toList(), ['b']);
  });

  test('clearAll empties the history', () async {
    await open('a');
    await open('b');
    await store.clearAll();
    expect(await store.watchRecent().first, isEmpty);
  });

  test(
    'latestPerRoom hides older same-room entries but keeps the rows',
    () async {
      final cozy = WatchContext.synced(server: 's', port: 8999, room: 'cozy');
      await open('a', context: cozy);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await open('b', context: cozy);

      final collapsed = await store
          .watchRecent(mode: HistoryMode.latestPerRoom)
          .first;
      expect(collapsed.map((e) => e.fileName).toList(), ['b']);

      final all = await store.watchRecent(mode: HistoryMode.everyVideo).first;
      expect(all.map((e) => e.fileName).toList(), ['b', 'a']);
    },
  );

  test('latestPerRoom shows Local and a synced room independently', () async {
    const path = r'D:\v\A.mkv';
    await open(path, name: 'A.mkv', context: roomA);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await open(path, name: 'A.mkv', context: local);

    final latest = await store
        .watchRecent(mode: HistoryMode.latestPerRoom)
        .first;
    expect(latest, hasLength(2));
    expect(latest.where((e) => e.isLocalContext), hasLength(1));
    expect(latest.where((e) => e.room == roomA.room), hasLength(1));

    final every = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(every, hasLength(2));
  });

  test(
    'latestPerRoom keeps the full-scan contract across a large history',
    () async {
      for (var i = 0; i < 205; i++) {
        await open(
          'f$i',
          context: WatchContext.synced(server: 's', port: 8999, room: 'room$i'),
        );
      }

      final all = await store
          .watchRecent(limit: 300, mode: HistoryMode.latestPerRoom)
          .first;
      expect(all, hasLength(205));
      expect(all.first.fileName, 'f204');
      expect(all.last.fileName, 'f0');

      final recent = await store
          .watchRecent(mode: HistoryMode.latestPerRoom)
          .first;
      expect(
        recent.map((e) => e.fileName).toList(),
        List.generate(6, (i) => 'f${204 - i}'),
      );
    },
  );

  test('latestPerRoom surfaces older distinct rooms when one room dominates '
      'recent history (PR #216 review)', () async {
    for (var i = 0; i < 4; i++) {
      await open(
        'old$i',
        context: WatchContext.synced(
          server: 's',
          port: 8999,
          room: 'oldroom$i',
        ),
      );
    }
    await open('solo');
    for (var i = 0; i < 210; i++) {
      await open(
        'flood$i',
        context: WatchContext.synced(server: 's', port: 8999, room: 'hot'),
      );
    }

    final list = await store.watchRecent(mode: HistoryMode.latestPerRoom).first;
    expect(list.map((e) => e.fileName).toList(), [
      'flood209',
      'solo',
      'old3',
      'old2',
      'old1',
      'old0',
    ]);
  });

  test(
    'latestPerRoom keeps Local as one bucket and fills limit after collapse',
    () async {
      final cozy = WatchContext.synced(server: 's', port: 8999, room: 'cozy');
      await open('a', context: cozy);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await open('b');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await open('c', context: cozy);

      final list = await store
          .watchRecent(limit: 2, mode: HistoryMode.latestPerRoom)
          .first;
      expect(list.map((e) => e.fileName).toList(), ['c', 'b']);
    },
  );

  test(
    'latestPerRoom merges trimmed room aliases onto one context key',
    () async {
      for (var i = 0; i < 5; i++) {
        await open(
          'old$i',
          context: WatchContext.synced(
            server: 's',
            port: 8999,
            room: 'oldroom$i',
          ),
        );
      }
      await open(
        'clean',
        context: WatchContext.synced(server: 's', port: 8999, room: 'cozy'),
      );
      await open(
        'tabbed',
        context: WatchContext.synced(server: 's', port: 8999, room: '\tcozy\t'),
      );
      await open(
        'nbsp',
        context: WatchContext.synced(
          server: 's',
          port: 8999,
          room: '\u00A0cozy\u00A0',
        ),
      );

      final list = await store
          .watchRecent(mode: HistoryMode.latestPerRoom)
          .first;
      expect(list.map((e) => e.fileName).toList(), [
        'nbsp',
        'old4',
        'old3',
        'old2',
        'old1',
        'old0',
      ]);
    },
  );

  test('two Local files collapse to the newest in latestPerRoom', () async {
    await open('g1');
    await open('g2');

    final latest = await store
        .watchRecent(mode: HistoryMode.latestPerRoom)
        .first;
    expect(latest.map((e) => e.fileName).toList(), ['g2']);

    final every = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    expect(every.map((e) => e.fileName).toList(), ['g2', 'g1']);
  });

  test('recordOpen stores endpoint pin provenance', () async {
    await store.recordOpen(
      filePath: r'D:\v\pin.mkv',
      fileName: 'pin.mkv',
      fileSizeBytes: 1,
      context: roomA,
      endpointPinned: true,
    );
    expect((await store.watchRecent().first).single.endpointPinned, isTrue);
  });

  test('updatePosition follows a new context after recordOpen', () async {
    await open(r'D:\v\move.mkv', context: roomA);
    expect(
      await seek(r'D:\v\move.mkv', context: roomA, positionMs: 9000),
      isTrue,
    );

    final roomMoved = WatchContext.synced(
      server: 'syncplay.pl',
      port: 8996,
      room: roomA.room!,
    );
    await store.recordOpen(
      filePath: r'D:\v\move.mkv',
      fileName: 'move.mkv',
      fileSizeBytes: 1,
      context: roomMoved,
      lastPositionMs: 9000,
    );
    final rows = await store.watchRecent(mode: HistoryMode.everyVideo).first;
    final landed = rows.singleWhere((e) => e.port == 8996);
    expect(landed.lastPositionMs, 9000);
  });

  test('recordOpen pin on a new row stays through a later unpinned open', () async {
    await store.recordOpen(
      filePath: r'D:\v\sticky.mkv',
      fileName: 'sticky.mkv',
      fileSizeBytes: 1,
      context: roomA,
      endpointPinned: true,
    );
    await store.recordOpen(
      filePath: r'D:\v\sticky.mkv',
      fileName: 'sticky.mkv',
      fileSizeBytes: 1,
      context: roomA,
      endpointPinned: false,
    );
    expect((await store.watchRecent().first).single.endpointPinned, isTrue);
  });

  test('kDartTrimWhitespace matches String.trim exactly across the BMP', () {
    final set = kDartTrimWhitespace.codeUnits.toSet();
    final mismatches = <String>[];
    for (var c = 0; c <= 0xFFFF; c++) {
      if (c >= 0xD800 && c <= 0xDFFF) continue;
      final dartTrims = String.fromCharCode(c).trim().isEmpty;
      if (dartTrims != set.contains(c)) {
        mismatches.add(
          'U+${c.toRadixString(16).padLeft(4, '0').toUpperCase()} '
          'dart:$dartTrims set:${set.contains(c)}',
        );
      }
    }
    expect(mismatches, isEmpty);
  });
}
