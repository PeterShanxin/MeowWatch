import 'history_entry.dart';
import 'history_mode.dart';
import 'saved_profile.dart';

/// Commands-in / streams-out access to saved connection profiles.
abstract class ProfileStore {
  /// Live list, most-recently-used first.
  Stream<List<SavedProfile>> watchProfiles();

  /// Insert or update the matching (server, port, room, username) profile and
  /// stamp it as just-used. [name] is the display label (usually the room).
  Future<void> saveUsed({
    required String name,
    required String server,
    required int port,
    required String room,
    required String username,
    String? password,
  });

  Future<void> delete(int id);
}

/// Commands-in / streams-out access to watch history.
abstract class HistoryStore {
  /// Live list, most-recently-played first. [mode] selects how same-room
  /// videos are shown: [HistoryMode.latestPerRoom] hides older same-room
  /// entries (view filter only — rows stay in storage), [HistoryMode.everyVideo]
  /// shows them all. The collapse runs before [limit] is applied.
  Stream<List<HistoryEntry>> watchRecent({
    int limit = 6,
    HistoryMode mode = HistoryMode.everyVideo,
  });

  /// Record (or refresh) that [filePath] was opened. Keeps the existing
  /// [lastPositionMs]; updates name/size/duration/room/username and bumps
  /// playedAt. [room]/[username] capture where it was watched (null outside a
  /// room).
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
    String? room,
    String? username,
  });

  /// Update the resume position for an already-recorded file (no-op if absent).
  /// Also backfills [durationMs] when given — duration is often unknown at
  /// open time (mpv hasn't probed the file yet), so the periodic position save
  /// is where the runtime — and thus the progress bar — gets filled in.
  Future<void> updatePosition({
    required String filePath,
    required int positionMs,
    int? durationMs,
  });

  /// Remove a single history entry.
  Future<void> delete(int id);

  /// Remove every history entry.
  Future<void> clearAll();
}
