import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/watch_context.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v2 schema exposes a usable Settings table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.settings)
        .insert(SettingsCompanion.insert(key: 'theme', value: 'noir'));
    final row = await (db.select(
      db.settings,
    )..where((t) => t.key.equals('theme'))).getSingle();
    expect(row.value, 'noir');
  });

  test('schemaVersion is 6', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 6);
  });

  test(
    'v5 history table exposes context_key + room endpoint columns',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.historyEntries)
          .insert(
            HistoryEntriesCompanion.insert(
              filePath: '/v/ep1.mkv',
              fileName: 'ep1.mkv',
              playedAt: DateTime(2026, 5, 30),
              contextKey: 'synced|syncplay.pl|8995|breezy-crow-66',
              room: const Value('breezy-crow-66'),
              username: const Value('meow'),
              server: const Value('syncplay.pl'),
              port: const Value(8995),
            ),
          );
      final row = await (db.select(
        db.historyEntries,
      )..where((t) => t.filePath.equals('/v/ep1.mkv'))).getSingle();
      expect(row.contextKey, 'synced|syncplay.pl|8995|breezy-crow-66');
      expect(row.room, 'breezy-crow-66');
      expect(row.username, 'meow');
      expect(row.server, 'syncplay.pl');
      expect(row.port, 8995);
    },
  );

  test(
    'v4 to current migrates roomful rows to room keys and roomless to local',
    () async {
      final dir = await Directory.systemTemp.createTemp('mw-hist-mig');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 't.db'));
      final raw = sqlite3.open(file.path);
      raw.execute('''
CREATE TABLE profiles (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  server TEXT NOT NULL,
  port INTEGER NOT NULL,
  room TEXT NOT NULL,
  username TEXT NOT NULL,
  password TEXT NULL,
  is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
  last_used_at INTEGER NULL,
  UNIQUE(server, port, room, username)
);
''');
      raw.execute('''
CREATE TABLE settings (
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (key)
);
''');
      raw.execute('''
CREATE TABLE history_entries (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  file_path TEXT NOT NULL UNIQUE,
  file_name TEXT NOT NULL,
  file_size_bytes INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NULL,
  last_position_ms INTEGER NOT NULL DEFAULT 0,
  played_at INTEGER NOT NULL,
  room TEXT NULL,
  username TEXT NULL,
  server TEXT NULL,
  port INTEGER NULL
);
''');
      final playedAt = DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000;
      raw.execute(
        '''
INSERT INTO history_entries (
  file_path, file_name, file_size_bytes, duration_ms, last_position_ms,
  played_at, room, username, server, port
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          r'D:\v\A.mkv',
          'A.mkv',
          1,
          600000,
          28 * 60 * 1000 + 8000,
          playedAt,
          'bouncy-snail',
          'meow',
          'syncplay.pl',
          8999,
        ],
      );
      raw.execute(
        '''
INSERT INTO history_entries (
  file_path, file_name, file_size_bytes, duration_ms, last_position_ms,
  played_at, room, username, server, port
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          r'D:\v\B.mkv',
          'B.mkv',
          1,
          120000,
          35000,
          playedAt + 1,
          null,
          null,
          null,
          null,
        ],
      );
      raw.execute('PRAGMA user_version = 4');
      raw.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final rows = await db.select(db.historyEntries).get();
      expect(rows, hasLength(2));

      final synced = rows.firstWhere((r) => r.filePath == r'D:\v\A.mkv');
      expect(synced.contextKey, 'synced|syncplay.pl|8999|bouncy-snail');
      expect(synced.room, 'bouncy-snail');
      expect(synced.username, 'meow');
      expect(synced.server, 'syncplay.pl');
      expect(synced.port, 8999);
      expect(synced.lastPositionMs, 28 * 60 * 1000 + 8000);
      expect(synced.durationMs, 600000);

      final solo = rows.firstWhere((r) => r.filePath == r'D:\v\B.mkv');
      expect(solo.contextKey, kLocalWatchContextKey);
      expect(solo.room, isNull);
      expect(solo.lastPositionMs, 35000);
      expect(solo.durationMs, 120000);
    },
  );

  test('v5 to v6 merges Local and synced rows for the same room', () async {
    final dir = await Directory.systemTemp.createTemp('mw-hist-room-mig');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 't.db'));
    final raw = sqlite3.open(file.path);
    raw.execute('''
CREATE TABLE profiles (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  server TEXT NOT NULL,
  port INTEGER NOT NULL,
  room TEXT NOT NULL,
  username TEXT NOT NULL,
  password TEXT NULL,
  is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
  last_used_at INTEGER NULL,
  UNIQUE(server, port, room, username)
);
''');
    raw.execute('''
CREATE TABLE settings (
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (key)
);
''');
    raw.execute('''
CREATE TABLE history_entries (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  file_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_size_bytes INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NULL,
  last_position_ms INTEGER NOT NULL DEFAULT 0,
  played_at INTEGER NOT NULL,
  context_key TEXT NOT NULL,
  room TEXT NULL,
  username TEXT NULL,
  server TEXT NULL,
  port INTEGER NULL,
  UNIQUE(file_path, context_key)
);
''');
    const path = r'D:\v\A.mkv';
    const room = 'nimble-rabbit-tosses-eager-teapot';
    raw.execute(
      '''
INSERT INTO history_entries (
  file_path, file_name, duration_ms, last_position_ms, played_at,
  context_key, room, username, server, port
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        path,
        'A.mkv',
        600000,
        109958,
        100,
        'synced|syncplay.pl|8995|$room',
        room,
        'meow',
        'syncplay.pl',
        8995,
      ],
    );
    raw.execute(
      '''
INSERT INTO history_entries (
  file_path, file_name, duration_ms, last_position_ms, played_at,
  context_key, room, username, server, port
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        path,
        'A.mkv',
        600000,
        124875,
        101,
        kLocalWatchContextKey,
        room,
        'meow',
        'syncplay.pl',
        8995,
      ],
    );
    raw.execute(
      '''
INSERT INTO history_entries (
  file_path, file_name, duration_ms, last_position_ms, played_at,
  context_key
) VALUES (?, ?, ?, ?, ?, ?)
''',
      [r'D:\v\legacy.mkv', 'legacy.mkv', 120000, 35000, 102, 'local'],
    );
    raw.execute('PRAGMA user_version = 5');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final rows = await db.select(db.historyEntries).get();
    expect(rows, hasLength(2));

    final merged = rows.firstWhere((r) => r.filePath == path);
    expect(merged.contextKey, 'synced|syncplay.pl|8995|$room');
    expect(merged.lastPositionMs, 124875);
    expect(merged.playedAt, DateTime.fromMillisecondsSinceEpoch(101000));
    expect(merged.room, room);

    final legacy = rows.firstWhere((r) => r.filePath.endsWith('legacy.mkv'));
    expect(legacy.contextKey, kLocalWatchContextKey);
    expect(legacy.lastPositionMs, 35000);
  });
}
