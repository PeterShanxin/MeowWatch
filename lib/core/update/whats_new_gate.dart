/// Pure rule for the post-update "what's new" modal.
///
/// Returns true when a recorded previous version ([lastSeen] non-null/non-empty)
/// differs from [current] — i.e. the user updated.
///
/// When no version is recorded, the user either just did a fresh install or is
/// an EXISTING user upgrading from a build that predates the `last_seen_version`
/// key (so it was never written). [hasPriorInstall] disambiguates: when true
/// (the DB already holds the user's data), the modal still fires for that first
/// post-key launch — the version that *introduces* the modal must not skip the
/// very users who updated into it. A genuinely fresh install
/// ([hasPriorInstall] false) returns false. The caller records [current] every
/// launch, so the modal shows at most once per version bump.
bool shouldShowWhatsNew({
  required String? lastSeen,
  required String current,
  bool hasPriorInstall = false,
}) {
  final prev = lastSeen?.trim() ?? '';
  if (prev.isEmpty) return hasPriorInstall;
  return prev != current.trim();
}
