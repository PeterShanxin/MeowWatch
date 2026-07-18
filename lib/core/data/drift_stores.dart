import 'package:drift/drift.dart';

import 'app_database.dart';
import 'history_collapse.dart';
import 'history_entry.dart';
import 'history_mode.dart';
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
  }) {
    // Single-statement upsert on the (server, port, room, username) unique
    // key — one round trip instead of select-then-insert/update (#199). The
    // conflict branch writes exactly what the old update path wrote: name,
    // password (null clears it), and lastUsedAt; isDefault stays untouched.
    final now = DateTime.now();
    return _db.into(_db.profiles).insert(
          ProfilesCompanion.insert(
            name: name,
            server: server,
            port: port,
            room: room,
            username: username,
            password: Value(password),
            lastUsedAt: Value(now),
          ),
          onConflict: DoUpdate(
            (old) => ProfilesCompanion(
              name: Value(name),
              password: Value(password),
              lastUsedAt: Value(now),
            ),
            target: [
              _db.profiles.server,
              _db.profiles.port,
              _db.profiles.room,
              _db.profiles.username,
            ],
          ),
        );
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
  Stream<List<HistoryEntry>> watchRecent({
    int limit = 6,
    HistoryMode mode = HistoryMode.everyVideo,
  }) {
    if (mode == HistoryMode.everyVideo) {
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
    // latestPerRoom: SQL selects the collapsed set directly — the latest
    // entry per room (ROW_NUMBER over the trimmed room key, newest-first by
    // playedAt then id) plus every roomless entry — so older distinct rooms
    // still surface when one room dominates recent history (#199, PR #216
    // review; a pre-collapse LIMIT is NOT equivalent — it starves older
    // rooms). Work per invalidation stays bounded where it actually hurt:
    // the old implementation materialized the whole table into Dart
    // (row → HistoryEntry mapping + list churn per emission), while the
    // single window pass here runs inside SQLite's engine and hands Dart at
    // most `limit` rows.
    //
    // TRIM/COALESCE mirror collapseHistory's grouping key (null/blank room =
    // "not in a room", kept always). SQL TRIM only strips ASCII spaces where
    // Dart trim() strips all Unicode whitespace; the collapseHistory
    // post-pass below re-applies the exact Dart key over the (tiny) selected
    // set, so any residue merges the way the original full scan did.
    final rows = _db.customSelect(
      'SELECT * FROM ('
      'SELECT h.*, '
      "TRIM(COALESCE(h.room, '')) AS room_key, "
      'ROW_NUMBER() OVER ('
      "PARTITION BY TRIM(COALESCE(h.room, '')) "
      'ORDER BY h.played_at DESC, h.id DESC'
      ') AS room_rank '
      'FROM history_entries h'
      ') '
      "WHERE room_rank = 1 OR room_key = '' "
      'ORDER BY played_at DESC, id DESC '
      'LIMIT ?',
      variables: [Variable<int>(limit)],
      readsFrom: {_db.historyEntries},
    );
    return rows.watch().map(
          (raw) => collapseHistory(
            raw.map((r) => _toModel(_db.historyEntries.map(r.data))).toList(),
            mode,
          ).take(limit).toList(),
        );
  }

  @override
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
    String? room,
    String? username,
    String? server,
    int? port,
  }) {
    // Single-statement upsert on the unique filePath — one round trip instead
    // of select-then-insert/update (#199). The conflict branch mirrors the
    // old update path column-for-column; `old.<column>` keeps the stored
    // value, and lastPositionMs is never listed so a re-open can't touch a
    // saved resume point.
    final now = DateTime.now();
    return _db.into(_db.historyEntries).insert(
          HistoryEntriesCompanion.insert(
            filePath: filePath,
            fileName: fileName,
            fileSizeBytes: Value(fileSizeBytes),
            durationMs: Value(durationMs),
            playedAt: now,
            room: Value(room),
            username: Value(username),
            server: Value(server),
            port: Value(port),
          ),
          onConflict: DoUpdate(
            (old) => HistoryEntriesCompanion.custom(
              fileName: Variable(fileName),
              fileSizeBytes: Variable(fileSizeBytes),
              // Same guard as updatePosition: a re-open commits the duration
              // captured at open time — often 0, mpv hasn't probed yet — and
              // must never clobber a runtime a periodic save already
              // backfilled (#208 review).
              durationMs: (durationMs != null && durationMs > 0)
                  ? Variable(durationMs)
                  : old.durationMs,
              playedAt: Variable(now),
              // Keep room metadata when this open isn't in a room.
              room: room != null ? Variable(room) : old.room,
              username: username != null ? Variable(username) : old.username,
              server: server != null ? Variable(server) : old.server,
              port: port != null ? Variable(port) : old.port,
            ),
            target: [_db.historyEntries.filePath],
          ),
        );
  }

  @override
  Future<bool> updatePosition({
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    final rows = await (_db.update(_db.historyEntries)
          ..where((t) => t.filePath.equals(filePath)))
        .write(HistoryEntriesCompanion(
      lastPositionMs: Value(positionMs),
      // Only write a real, positive runtime — never clobber a known duration
      // with a 0 from a not-yet-probed frame.
      durationMs: (durationMs != null && durationMs > 0)
          ? Value(durationMs)
          : const Value.absent(),
    ));
    return rows > 0;
  }

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
        server: r.server,
        port: r.port,
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

  @override
  Future<bool> hasAnySettings() async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(kLastSeenVersionKey).not())
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }
}
