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

  group('hasAnySettings', () {
    test('false on an empty store', () async {
      expect(await store.hasAnySettings(), isFalse);
    });

    test('true once a real setting is written', () async {
      await store.set(kThemeSettingKey, 'noir');
      expect(await store.hasAnySettings(), isTrue);
    });

    test('ignores the app-written last-seen version', () async {
      // A fresh install records last_seen each launch; that alone must not
      // count as "the user has used this before".
      await store.set(kLastSeenVersionKey, '0.33.0-alpha');
      expect(await store.hasAnySettings(), isFalse);
      await store.set(kLogLevelSettingKey, 'neat');
      expect(await store.hasAnySettings(), isTrue);
    });
  });
}
