import 'playback_state.dart';
import 'video_core.dart';

/// Wait for a just-issued [VideoCore.load] to either open or fail, returning
/// `true` on success and `false` on error.
///
/// mpv reports a bad source (an unreachable / non-video / expired link, or a
/// moved / unreadable local file) on its error stream *after* `load()` has
/// returned, and media_kit emits a `paused` tick the instant `open()` returns —
/// before that error. So we wait for positive evidence ([isPlaybackOpen]) or an
/// error, never settling on the bare paused tick.
///
/// On [timeout] we resolve optimistically *only* if the source has at least
/// reached `paused` — a valid live stream may stay `paused` with no duration
/// indefinitely, and we'd rather announce a slow-but-good stream than hang. A
/// source still `loading` (or `idle`) at the timeout never opened — a hang or a
/// late error — so it resolves to `false`, not a false "loaded".
Future<bool> awaitOpenResult(
  VideoCore core, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  bool isError(PlaybackState s) => s.status == PlaybackStatus.error;

  // Already settled (the event arrived before we looked).
  if (isError(core.state)) return false;
  if (isPlaybackOpen(core.state)) return true;

  final settled = await core.stateStream
      .firstWhere((s) => isError(s) || isPlaybackOpen(s))
      .timeout(timeout, onTimeout: () => core.state);

  if (isError(settled)) return false;
  if (isPlaybackOpen(settled)) return true;
  // Timed out without a confirmed open: trust a live stream that has reached
  // `paused` (no duration, but no error in [timeout] either); reject anything
  // still `loading`/`idle`.
  return settled.status == PlaybackStatus.paused;
}
