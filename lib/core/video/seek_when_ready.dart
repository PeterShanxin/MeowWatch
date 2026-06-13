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
Future<void> seekWhenReady(
  VideoCore core,
  Duration target, {
  String? source,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (target <= Duration.zero) return;
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
  await core.seek(target);
}
