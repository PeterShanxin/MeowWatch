import 'semver.dart';

/// Pure rule for the post-update "what's new" modal.
///
/// Returns true only when [current] is a genuine UPGRADE over the recorded
/// [lastSeen] — i.e. strictly newer by semver. A same or *older* current
/// version returns false: showing "what's new" on a version drop is wrong, and
/// (the bug this guards) when two installs of MeowWatch share one machine's data
/// store — a released production copy and an in-development build — an older
/// build launching must not re-trigger the modal just because the newer build
/// recorded its version. Pair with [lastSeenToPersist] so the recorded version
/// only ever advances.
///
/// When no version is recorded, the user either just did a fresh install or is
/// an EXISTING user upgrading from a build that predates the `last_seen_version`
/// key (so it was never written). [hasPriorInstall] disambiguates: when true
/// (the DB already holds the user's data), the modal still fires for that first
/// post-key launch — the version that *introduces* the modal must not skip the
/// very users who updated into it. A genuinely fresh install
/// ([hasPriorInstall] false) returns false.
bool shouldShowWhatsNew({
  required String? lastSeen,
  required String current,
  bool hasPriorInstall = false,
}) {
  final prev = lastSeen?.trim() ?? '';
  if (prev.isEmpty) return hasPriorInstall;
  return isVersionNewer(current.trim(), prev);
}

/// The value to persist for the last-seen version, or null when no write is
/// needed.
///
/// High-water mark: advances to [current] only when it is newer than the
/// [stored] record (or none is stored). An older build run on the same machine
/// never lowers it, so two installs sharing one data store can no longer
/// ping-pong the recorded version and re-fire the modal on every switch.
String? lastSeenToPersist({
  required String? stored,
  required String current,
}) {
  final prev = stored?.trim() ?? '';
  final cur = current.trim();
  if (prev.isEmpty) return cur;
  return isVersionNewer(cur, prev) ? cur : null;
}
