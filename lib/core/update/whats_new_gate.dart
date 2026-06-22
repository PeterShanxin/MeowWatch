/// Pure rule for the post-update "what's new" modal.
///
/// Returns true only when a PREVIOUS version was recorded ([lastSeen] non-null
/// and non-empty) and it differs from [current] — i.e. the user updated. A fresh
/// install (no record) returns false. The caller is expected to record [current]
/// on every launch, so the modal shows at most once per version bump.
bool shouldShowWhatsNew({required String? lastSeen, required String current}) {
  if (lastSeen == null) return false;
  final prev = lastSeen.trim();
  if (prev.isEmpty) return false;
  return prev != current.trim();
}
