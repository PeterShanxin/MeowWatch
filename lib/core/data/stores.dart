import 'history_entry.dart';
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
  /// Live list, most-recently-played first.
  Stream<List<HistoryEntry>> watchRecent({int limit = 6});

  /// Record (or refresh) that [filePath] was opened. Keeps the existing
  /// [lastPositionMs]; updates name/size/duration and bumps playedAt.
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
  });

  /// Update the resume position for an already-recorded file (no-op if absent).
  Future<void> updatePosition({
    required String filePath,
    required int positionMs,
  });
}
