import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/drift_stores.dart';
import 'package:meowwatch/core/data/settings_store.dart';

void main() {
  late AppDatabase db;
  late SettingsStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftSettingsStore(db);
  });
  tearDown(() => db.close());

  test('get returns null for a missing key', () async {
    expect(await store.get('theme'), isNull);
  });

  test('set then get round-trips', () async {
    await store.set('theme', 'aurora');
    expect(await store.get('theme'), 'aurora');
  });

  test('set overwrites an existing key', () async {
    await store.set('theme', 'noir');
    await store.set('theme', 'cozy');
    expect(await store.get('theme'), 'cozy');
  });
}
