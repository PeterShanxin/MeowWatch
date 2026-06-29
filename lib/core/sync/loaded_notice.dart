/// The brief over-video banner shown right after a video opens, or null when
/// there is nothing worth announcing.
///
/// It only claims "in sync" when a friend is connected ([syncHealthy]) and the
/// files don't visibly mismatch ([fileMismatch] false). Solo, there's nothing to
/// be in sync with; mismatched, the dedicated mismatch banner already warns — so
/// in both cases this stays silent and the chat "Loaded …" line carries it.
String? loadedInSyncNotice({
  required bool syncHealthy,
  required bool fileMismatch,
}) {
  if (!syncHealthy || fileMismatch) return null;
  return '✓ Loaded — in sync!';
}
