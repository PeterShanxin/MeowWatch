import 'playback_state.dart';
import 'video_core.dart';

/// Whether [state] is positive evidence that the source actually opened.
///
/// media_kit emits a `playing=false`/`paused` tick the *instant* `open()`
/// returns — before it reports a failing source on the error stream — so a bare
/// `paused` is not yet proof of a good open. A genuine open also reports a
/// non-zero duration (or reaches `playing`/`ended`), which a broken link never
/// does, so we require that before declaring success.
bool _opened(PlaybackState state) {
  switch (state.status) {
    case PlaybackStatus.playing:
    case PlaybackStatus.ended:
      return true;
    case PlaybackStatus.paused:
      return state.duration > Duration.zero;
    case PlaybackStatus.idle:
    case PlaybackStatus.loading:
    case PlaybackStatus.error:
      return false;
  }
}

/// Wait for a just-issued [VideoCore.load] to either open or fail, returning
/// `true` on success and `false` on error.
///
/// mpv reports a bad source (an unreachable / non-video / expired link, or a
/// moved / unreadable local file) on its error stream *after* `load()` has
/// returned. Callers that announce a load to the room, persist it to history,
/// or post a "Loaded …" chat line must wait for the real outcome first, or a
/// failed source would surface to peers and history as if it had loaded.
///
/// A [timeout] resolves to `true` (optimistic): a valid live stream may stay
/// `paused` with no duration indefinitely, and we'd rather announce a
/// slow-but-good source than hang the caller forever.
Future<bool> awaitOpenResult(
  VideoCore core, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  bool isError(PlaybackState s) => s.status == PlaybackStatus.error;

  // Already settled (the event arrived before we looked).
  if (isError(core.state)) return false;
  if (_opened(core.state)) return true;

  final settled = await core.stateStream
      .firstWhere((s) => isError(s) || _opened(s))
      .timeout(timeout, onTimeout: () => core.state);
  return !isError(settled);
}
