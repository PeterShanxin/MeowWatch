// Builders for the empty-screen "load a video to join" prompt — the persistent
// nudge shown to whoever is still on the no-video screen while a friend is
// already set up.
//
// Two triggers, so neither side is left guessing:
//  - a peer announced a loaded file (they're ready, waiting on us) — #116
//  - a peer started playback before we'd loaded anything — #60
//
// Each returns null when the prompt shouldn't apply (we already have our own
// file, or the event is our own echo), so the caller can assign the result and
// only overwrite the current prompt when one is produced. Wording lives here so
// the file- and play-triggered prompts stay consistent and don't fight.

/// A peer announced a loaded file while we have nothing loaded (#116). Mirrors
/// the loader's "hasn't loaded a video yet" heads-up from the other direction.
String? peerLoadedJoinPrompt({
  required bool localHasFile,
  required String? localUsername,
  required String peerUsername,
  required String peerFileName,
}) {
  if (localHasFile) return null;
  if (peerUsername == localUsername) return null;
  return '$peerUsername loaded "$peerFileName" — load the same video to join';
}

/// A peer drove playback while we have nothing loaded (#60).
String? peerStartedPlaybackJoinPrompt({
  required bool localHasFile,
  required String? localUsername,
  required String peerUsername,
}) {
  if (localHasFile) return null;
  if (peerUsername == localUsername) return null;
  return '$peerUsername started playback — load a video to join';
}
