/// How the "Continue watching" list treats multiple videos watched in the same
/// room. [latestPerRoom] keeps only the most-recently-played file per room
/// (older same-room entries are hidden, not deleted); [everyVideo] shows them
/// all. Persisted under `kHistoryModeSettingKey` via [storageName].
enum HistoryMode {
  latestPerRoom,
  everyVideo;

  String get storageName => switch (this) {
        HistoryMode.latestPerRoom => 'latest_per_room',
        HistoryMode.everyVideo => 'every_video',
      };
}

/// Parse a persisted [HistoryMode.storageName]. Absent or unrecognized values
/// fall back to [HistoryMode.latestPerRoom] — the product default.
HistoryMode historyModeFromName(String? name) {
  for (final mode in HistoryMode.values) {
    if (mode.storageName == name) return mode;
  }
  return HistoryMode.latestPerRoom;
}
