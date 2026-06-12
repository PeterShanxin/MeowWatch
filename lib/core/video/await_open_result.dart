import 'playback_state.dart';
import 'video_core.dart';

/// Whether [status] is a settled outcome of a load — either a playable state or
/// an outright failure (no longer `loading`).
bool _settled(PlaybackStatus status) =>
    status == PlaybackStatus.error ||
    status == PlaybackStatus.playing ||
    status == PlaybackStatus.paused ||
    status == PlaybackStatus.ended;

/// Wait for a just-issued [VideoCore.load] to either open or fail, returning
/// `true` on success and `false` on error.
///
/// mpv reports a bad source (an unreachable / non-video / expired link) on its
/// error stream *after* `load()` has already returned. Callers that announce a
/// load to the room, persist it to history, or post a "Loaded …" chat line must
/// wait for the real outcome first, or a failed link would surface to peers and
/// history as if it had loaded.
///
/// A [timeout] resolves to `true` (optimistic): a valid live stream may never
/// report a duration, and we'd rather announce a slow-but-good source than hang
/// the caller forever.
Future<bool> awaitOpenResult(
  VideoCore core, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  // Already settled (e.g. the error/paused event arrived before we looked).
  if (_settled(core.state.status)) {
    return core.state.status != PlaybackStatus.error;
  }
  final settledState = await core.stateStream
      .firstWhere((s) => _settled(s.status))
      .timeout(timeout, onTimeout: () => core.state);
  return settledState.status != PlaybackStatus.error;
}
