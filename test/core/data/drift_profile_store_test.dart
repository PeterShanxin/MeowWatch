import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/drift_stores.dart';

void main() {
  late AppDatabase db;
  late DriftProfileStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftProfileStore(db);
  });

  tearDown(() async => db.close());

  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('saveUsed inserts a new profile', () async {
    await store.saveUsed(
      name: 'cozy-fox-42',
      server: 'syncplay.pl',
      port: 8999,
      room: 'cozy-fox-42',
      username: 'lin',
    );
    await tick();
    final list = await store.watchProfiles().first;
    expect(list, hasLength(1));
    expect(list.single.room, 'cozy-fox-42');
    expect(list.single.password, isNull);
    expect(list.single.lastUsedAt, isNotNull);
  });

  test('saveUsed on the same room/user updates instead of duplicating',
      () async {
    await store.saveUsed(
      name: 'r',
      server: 's',
      port: 1,
      room: 'r',
      username: 'u',
    );
    await store.saveUsed(
      name: 'r',
      server: 's',
      port: 1,
      room: 'r',
      username: 'u',
      password: 'secret',
    );
    final list = await store.watchProfiles().first;
    expect(list, hasLength(1));
    expect(list.single.password, 'secret');
  });

  test('watchProfiles orders most-recently-used first', () async {
    await store.saveUsed(
        name: 'a', server: 's', port: 1, room: 'a', username: 'u');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.saveUsed(
        name: 'b', server: 's', port: 1, room: 'b', username: 'u');
    final list = await store.watchProfiles().first;
    expect(list.map((p) => p.room).toList(), ['b', 'a']);
  });

  test('delete removes a profile', () async {
    await store.saveUsed(
        name: 'a', server: 's', port: 1, room: 'a', username: 'u');
    final saved = (await store.watchProfiles().first).single;
    await store.delete(saved.id);
    expect(await store.watchProfiles().first, isEmpty);
  });
}
