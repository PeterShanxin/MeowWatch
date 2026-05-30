import 'package:drift/drift.dart' show Value;
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

  test('schemaVersion is 3', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 3);
  });

  test('v3 history table exposes room + username columns', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.historyEntries).insert(
          HistoryEntriesCompanion.insert(
            filePath: '/v/ep1.mkv',
            fileName: 'ep1.mkv',
            playedAt: DateTime(2026, 5, 30),
            room: const Value('breezy-crow-66'),
            username: const Value('meow'),
          ),
        );
    final row = await (db.select(db.historyEntries)
          ..where((t) => t.filePath.equals('/v/ep1.mkv')))
        .getSingle();
    expect(row.room, 'breezy-crow-66');
    expect(row.username, 'meow');
  });
}
