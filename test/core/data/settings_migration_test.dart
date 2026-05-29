import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';

void main() {
  test('v2 schema exposes a usable Settings table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.settings).insert(
          SettingsCompanion.insert(key: 'theme', value: 'noir'),
        );
    final row = await (db.select(db.settings)
          ..where((t) => t.key.equals('theme')))
        .getSingle();
    expect(row.value, 'noir');
  });

  test('schemaVersion is 2', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 2);
  });
}
