import 'peer_state.dart';

/// Classify a followed peer state into a deliberate [SyncActivity], or null
/// when it is not a friend-action worth announcing.
///
/// Fed the relayed [global] state plus our OWN play state captured just BEFORE
/// we apply it — the Syncplay client calls this at the decision point, so the
/// locals are still the pre-jump snapshot (race-free; deriving this in the UI
/// from the applied stream would be timing-fragile).
///
/// Suppressed (→ null):
///   * no [PeerPlayState.setBy] — cannot attribute who did it
///   * a seek landing within [seekNoiseThreshold] of where we already are
///   * a drift rewind: no seek flag and no pause/play flip (the client nudging
///     us back into the room is not a deliberate action).
SyncActivity? classifySyncActivity({
  required PeerPlayState global,
  required bool localPaused,
  required Duration localPosition,
  Duration seekNoiseThreshold = const Duration(seconds: 1),
}) {
  final user = global.setBy;
  if (user == null) return null;

  if (global.doSeek) {
    final delta = global.position - localPosition;
    if (delta.abs() <= seekNoiseThreshold) return null;
    return SyncActivity(
      kind: delta > Duration.zero
          ? SyncActivityKind.seekedForward
          : SyncActivityKind.seekedBack,
      username: user,
      position: global.position,
    );
  }

  if (global.paused != localPaused) {
    return SyncActivity(
      kind: global.paused ? SyncActivityKind.paused : SyncActivityKind.played,
      username: user,
      position: global.position,
    );
  }

  return null;
}

/// Classify the LOCAL user's own play/pause/seek into a [SyncActivity] so it can
/// be announced on our own screen (issue #27), mirroring what peers already see.
///
/// The Syncplay bridge detects a local change and calls this with the new local
/// state plus the snapshot from just before it. Seek direction comes from the
/// position delta; a pause/play flip from the paused-flag change. A tick that is
/// neither (steady playback) returns null.
SyncActivity? classifyLocalActivity({
  required bool doSeek,
  required bool paused,
  required bool wasPaused,
  required Duration position,
  required Duration previousPosition,
  required String username,
}) {
  if (doSeek) {
    final delta = position - previousPosition;
    return SyncActivity(
      kind: delta.isNegative
          ? SyncActivityKind.seekedBack
          : SyncActivityKind.seekedForward,
      username: username,
      position: position,
    );
  }

  if (paused != wasPaused) {
    return SyncActivity(
      kind: paused ? SyncActivityKind.paused : SyncActivityKind.played,
      username: username,
      position: position,
    );
  }

  return null;
}
