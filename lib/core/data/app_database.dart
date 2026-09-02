import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../sync/syncplay_endpoints.dart';
import 'app_support_dir.dart';
import 'watch_context.dart';

part 'app_database.g.dart';

@DataClassName('ProfileRow')
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get server => text()();
  IntColumn get port => integer()();
  TextColumn get room => text()();
  TextColumn get username => text()();
  TextColumn get password => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  BoolColumn get endpointPinned =>
      boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {server, port, room, username},
  ];
}

@DataClassName('HistoryRow')
class HistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get lastPositionMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get playedAt => dateTime()();

  /// Legacy roomless `local`, or stable `synced|server|port|room` regardless of
  /// the effective session mode. Unique with [filePath].
  TextColumn get contextKey => text()();
  TextColumn get room => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get server => text().nullable()();
  IntColumn get port => integer().nullable()();
  BoolColumn get endpointPinned =>
      boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {filePath, contextKey},
  ];
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Profiles, HistoryEntries, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(settings);
      if (from < 3) {
        await m.addColumn(historyEntries, historyEntries.room);
        await m.addColumn(historyEntries, historyEntries.username);
      }
      if (from < 4) {
        await m.addColumn(historyEntries, historyEntries.server);
        await m.addColumn(historyEntries, historyEntries.port);
      }
      if (from < 5) await _migrateHistoryToContextKeys();
      if (from < 6) await _migrateHistoryToStableRoomKeys();
      if (from < 7) {
        await m.addColumn(profiles, profiles.endpointPinned);
        await m.addColumn(historyEntries, historyEntries.endpointPinned);
        await _pinLegacyNonPublicEndpoints();
      }
    },
  );

  /// v5: drop file_path UNIQUE, add context_key, UNIQUE(file_path, context_key).
  /// Roomful rows become synced-context; roomless rows become Local.
  Future<void> _migrateHistoryToContextKeys() async {
    await customStatement('''
CREATE TABLE history_entries_v5 (
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
    await customStatement('''
INSERT INTO history_entries_v5 (
  id, file_path, file_name, file_size_bytes, duration_ms, last_position_ms,
  played_at, context_key, room, username, server, port
)
SELECT
  id, file_path, file_name, file_size_bytes, duration_ms, last_position_ms,
  played_at,
  CASE
    WHEN room IS NOT NULL AND TRIM(room) != ''
      THEN 'synced|' || COALESCE(server, '') || '|' || COALESCE(port, 0)
        || '|' || TRIM(room)
    ELSE 'local'
  END,
  room, username, server, port
FROM history_entries;
''');
    await customStatement('DROP TABLE history_entries;');
    await customStatement(
      'ALTER TABLE history_entries_v5 RENAME TO history_entries;',
    );
  }

  /// v6: a real room is the stable history identity whether the effective
  /// session mode is Local or synced. Normalize roomful `local` rows onto the
  /// existing room key and, when both forms exist, keep the most recently
  /// played row (id breaks whole-second ties).
  Future<void> _migrateHistoryToStableRoomKeys() async {
    await customStatement('''
CREATE TABLE history_entries_v6 (
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
    await customStatement(
      '''
WITH normalized AS (
  SELECT
    id, file_path, file_name, file_size_bytes, duration_ms, last_position_ms,
    played_at,
    CASE
      WHEN room IS NOT NULL AND TRIM(room, ?1) != ''
        THEN 'synced|' || TRIM(COALESCE(server, ''), ?1) || '|'
          || COALESCE(port, 0) || '|' || TRIM(room, ?1)
      ELSE 'local'
    END AS normalized_context_key,
    room, username, server, port
  FROM history_entries
),
ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY file_path, normalized_context_key
      ORDER BY played_at DESC, id DESC
    ) AS context_rank
  FROM normalized
)
INSERT INTO history_entries_v6 (
  id, file_path, file_name, file_size_bytes, duration_ms, last_position_ms,
  played_at, context_key, room, username, server, port
)
SELECT
  id, file_path, file_name, file_size_bytes, duration_ms, last_position_ms,
  played_at, normalized_context_key, room, username, server, port
FROM ranked
WHERE context_rank = 1;
''',
      [kDartTrimWhitespace],
    );
    await customStatement('DROP TABLE history_entries;');
    await customStatement(
      'ALTER TABLE history_entries_v6 RENAME TO history_entries;',
    );
  }

  /// v7: existing public-list rows stay discoverable (column default false).
  /// Self-hosted and any host MeowWatch never chose are pinned.
  Future<void> _pinLegacyNonPublicEndpoints() async {
    final profileRows = await select(profiles).get();
    for (final row in profileRows) {
      if (isPublicSyncplayCandidate(
        SyncplayEndpoint(host: row.server, port: row.port),
      )) {
        continue;
      }
      await (update(profiles)..where((t) => t.id.equals(row.id))).write(
        const ProfilesCompanion(endpointPinned: Value(true)),
      );
    }
    final historyRows = await select(historyEntries).get();
    for (final row in historyRows) {
      final host = row.server;
      final port = row.port;
      if (host == null || port == null) continue;
      if (isPublicSyncplayCandidate(SyncplayEndpoint(host: host, port: port))) {
        continue;
      }
      await (update(historyEntries)..where((t) => t.id.equals(row.id))).write(
        const HistoryEntriesCompanion(endpointPinned: Value(true)),
      );
    }
  }
}

/// Opens the on-disk database under the app's support directory
/// (Windows: %APPDATA%\<org>\meowwatch\meowwatch.db or similar), or under the
/// [kDataDirEnvVar] override when set, so a dev/test build can keep its data
/// separate from a production copy on the same machine.
Future<AppDatabase> openAppDatabase() async {
  final dir = await resolveAppSupportDir();
  final file = File(p.join(dir.path, 'meowwatch.db'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}
