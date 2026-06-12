/// How much diagnostic detail the [DebugLog] writes.
///
/// Persisted by `storageName` under `kLogLevelSettingKey`. The default is
/// [verbose] so the intermittent co-watch A/V lag is fully captured the next
/// time it strikes, without the user having to flip anything on first.
enum LogLevel {
  /// Logging disabled — nothing is written and no rotating file is opened.
  off,

  /// Meaningful events only: applied follows, reconnects/drops, errors, and
  /// log markers. Drops the per-heartbeat `<<`/`>>` and `apply=false` spam.
  neat,

  /// Full protocol trace (every `<<`/`>>` line and every FOLLOW decision).
  verbose;

  /// Stable lowercase token written to settings storage.
  String get storageName => name;
}

/// Parse a persisted [LogLevel.storageName] back to a level.
///
/// Tolerant of casing/whitespace; null, empty, or unknown input falls back to
/// [LogLevel.verbose] (the product default).
LogLevel logLevelFromName(String? name) {
  final key = name?.trim().toLowerCase();
  for (final level in LogLevel.values) {
    if (level.storageName == key) return level;
  }
  return LogLevel.verbose;
}
