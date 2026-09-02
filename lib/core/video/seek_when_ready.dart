import 'playback_state.dart';
import 'video_core.dart';

/// Seek [core] to [target] once the media is open and its duration is known.
///
/// media_kit drops a seek issued before the media is open and its duration is
/// known — the file would just start at 0. So we wait (bounded by [timeout])
/// for the first non-zero duration, then seek. A non-positive [target] is a
/// no-op (nothing to resume to).
///
/// Pass [source] (the path/URL being resumed) to scope the wait: if a newer load
/// swaps the source while we're waiting, we skip the seek rather than apply this
/// resume position to the wrong media. If the core is disposed mid-wait (the user
/// left/closed the room), the wait ends without throwing and the seek is skipped.
///
/// A paused media backend can occasionally complete `seek()` without publishing
/// the requested position. Resume therefore confirms that the position landed
/// and retries a small, bounded number of times. It never starts playback.
Future<void> seekWhenReady(
  VideoCore core,
  Duration target, {
  String? source,
  Duration timeout = const Duration(seconds: 8),
  Duration retryDelay = const Duration(milliseconds: 250),
  int maxAttempts = 3,
}) async {
  if (target <= Duration.zero || maxAttempts <= 0) return;
  bool superseded() => source != null && core.state.filePath != source;
  if (superseded()) return;

  if (core.state.duration <= Duration.zero) {
    // `orElse` keeps a closed stream (core disposed on leave/close) from
    // throwing a StateError; the disposed guard below then skips the seek. The
    // predicate also completes on a source swap so we don't wait out the full
    // timeout for a superseded resume.
    await core.stateStream
        .firstWhere(
          (PlaybackState s) =>
              s.duration > Duration.zero ||
              (source != null && s.filePath != source),
          orElse: () => core.state,
        )
        .timeout(timeout, onTimeout: () => core.state);
  }

  // Don't seek a torn-down core, or one a newer load now owns.
  if (core.isDisposed || superseded()) return;

  // Position ticks are quantized and can land a little either side of the
  // requested timestamp. This is tight enough to distinguish a real resume
  // from the unchanged 0:00 state while avoiding pointless repeat seeks.
  bool landed() =>
      (core.state.position - target).abs() <= const Duration(seconds: 1);

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    await core.seek(target);
    if (core.isDisposed || superseded() || landed()) return;
    if (attempt == maxAttempts - 1) return;

    // Give the backend's async position stream a chance to confirm the seek.
    // A closed stream resolves through orElse; a newer source also wakes the
    // wait immediately so an abandoned resume never burns the retry budget.
    await core.stateStream
        .firstWhere((_) => superseded() || landed(), orElse: () => core.state)
        .timeout(retryDelay, onTimeout: () => core.state);
    if (core.isDisposed || superseded() || landed()) return;
  }
}
