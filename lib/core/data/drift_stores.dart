import 'package:drift/drift.dart';

import 'app_database.dart';
import 'history_entry.dart';
import 'saved_profile.dart';
import 'settings_store.dart';
import 'stores.dart';

class DriftProfileStore implements ProfileStore {
  DriftProfileStore(this._db);

  final AppDatabase _db;

  @override
  Stream<List<SavedProfile>> watchProfiles() {
    // drift stores DateTime as whole unix seconds, so two writes within the
    // same second tie on lastUsedAt. id (autoincrement) is the stable
    // tie-break: a newer row always has a higher id.
    final query = _db.select(_db.profiles)
      ..orderBy([
        (t) => OrderingTerm(expression: t.lastUsedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  @override
  Future<void> saveUsed({
    required String name,
    required String server,
    required int port,
    required String room,
    required String username,
    String? password,
  }) async {
    final existing = await (_db.select(_db.profiles)
          ..where((t) =>
              t.server.equals(server) &
              t.port.equals(port) &
              t.room.equals(room) &
              t.username.equals(username)))
        .getSingleOrNull();

    final companion = ProfilesCompanion(
      name: Value(name),
      server: Value(server),
      port: Value(port),
      room: Value(room),
      username: Value(username),
      password: Value(password),
      lastUsedAt: Value(DateTime.now()),
    );

    if (existing == null) {
      await _db.into(_db.profiles).insert(companion);
    } else {
      await (_db.update(_db.profiles)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
  }

  @override
  Future<void> delete(int id) =>
      (_db.delete(_db.profiles)..where((t) => t.id.equals(id))).go();

  SavedProfile _toModel(ProfileRow r) => SavedProfile(
        id: r.id,
        name: r.name,
        server: r.server,
        port: r.port,
        room: r.room,
        username: r.username,
        password: r.password,
        lastUsedAt: r.lastUsedAt,
      );
}

class DriftHistoryStore implements HistoryStore {
  DriftHistoryStore(this._db);

  final AppDatabase _db;

  @override
  Stream<List<HistoryEntry>> watchRecent({int limit = 6}) {
    // playedAt ties at whole-second resolution; id desc is the stable
    // tie-break so the newest write wins.
    final query = _db.select(_db.historyEntries)
      ..orderBy([
        (t) => OrderingTerm(expression: t.playedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  @override
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
    String? room,
    String? username,
  }) async {
    final existing = await (_db.select(_db.historyEntries)
          ..where((t) => t.filePath.equals(filePath)))
        .getSingleOrNull();

    if (existing == null) {
      await _db.into(_db.historyEntries).insert(
            HistoryEntriesCompanion.insert(
              filePath: filePath,
              fileName: fileName,
              fileSizeBytes: Value(fileSizeBytes),
              durationMs: Value(durationMs),
              playedAt: DateTime.now(),
              room: Value(room),
              username: Value(username),
            ),
          );
    } else {
      await (_db.update(_db.historyEntries)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        HistoryEntriesCompanion(
          fileName: Value(fileName),
          fileSizeBytes: Value(fileSizeBytes),
          durationMs: Value(durationMs ?? existing.durationMs),
          playedAt: Value(DateTime.now()),
          // Keep the previous room/username when this open isn't in a room.
          room: Value(room ?? existing.room),
          username: Value(username ?? existing.username),
        ),
      );
    }
  }

  @override
  Future<void> updatePosition({
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) =>
      (_db.update(_db.historyEntries)..where((t) => t.filePath.equals(filePath)))
          .write(HistoryEntriesCompanion(
        lastPositionMs: Value(positionMs),
        // Only write a real, positive runtime — never clobber a known duration
        // with a 0 from a not-yet-probed frame.
        durationMs: (durationMs != null && durationMs > 0)
            ? Value(durationMs)
            : const Value.absent(),
      ));

  @override
  Future<void> delete(int id) =>
      (_db.delete(_db.historyEntries)..where((t) => t.id.equals(id))).go();

  @override
  Future<void> clearAll() => _db.delete(_db.historyEntries).go();

  HistoryEntry _toModel(HistoryRow r) => HistoryEntry(
        id: r.id,
        filePath: r.filePath,
        fileName: r.fileName,
        fileSizeBytes: r.fileSizeBytes,
        durationMs: r.durationMs,
        lastPositionMs: r.lastPositionMs,
        playedAt: r.playedAt,
        room: r.room,
        username: r.username,
      );
}

class DriftSettingsStore implements SettingsStore {
  DriftSettingsStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> set(String key, String value) {
    return _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }
}
