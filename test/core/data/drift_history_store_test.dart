import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/drift_stores.dart';

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

  test('updatePosition on an unknown path is a no-op', () async {
    await store.updatePosition(filePath: r'D:\nope.mkv', positionMs: 100);
    expect(await store.watchRecent().first, isEmpty);
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
}
