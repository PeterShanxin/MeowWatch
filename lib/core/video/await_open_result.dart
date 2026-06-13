import 'playback_state.dart';
import 'video_core.dart';

/// Wait for a just-issued [VideoCore.load] of [source] to either open or fail,
/// returning `true` on success and `false` on error/supersede.
///
/// mpv reports a bad source (an unreachable / non-video / expired link, or a
/// moved / unreadable local file) on its error stream *after* `load()` has
/// returned, and media_kit emits a `paused` tick the instant `open()` returns —
/// before that error. So we wait for positive evidence ([isPlaybackOpen]) or an
/// error, never settling on the bare paused tick.
///
/// The wait is scoped to [source]: once `filePath` no longer matches (a newer
/// load superseded this one), we stop and return `false` — the newer load owns
/// the core state and reports its own outcome. This keeps a stale/slow load from
/// consuming a state, error, or open that now belongs to a different source.
///
/// On [timeout] we resolve optimistically only on positive-enough evidence: a
/// `paused` source (a valid live stream may stay `paused` with no duration
/// indefinitely, and we'd rather announce a slow-but-good stream than hang), or a
/// `playing` source whose position has advanced past zero (frames are flowing). A
/// `playing` source still at position zero is a premature user play over a
/// not-yet-open source and is rejected. A source still `loading` (or `idle`) at
/// the timeout never opened — a hang or a late error — so it resolves to `false`.
Future<bool> awaitOpenResult(
  VideoCore core, {
  required String source,
  Duration timeout = const Duration(seconds: 12),
}) async {
  bool superseded(PlaybackState s) => s.filePath != source;
  bool isError(PlaybackState s) => s.status == PlaybackStatus.error;

  // Already settled (the event arrived before we looked).
  if (superseded(core.state) || isError(core.state)) return false;
  if (isPlaybackOpen(core.state)) return true;

  // `orElse` handles the stream closing first — e.g. the user leaves/closes the
  // room (HomeScreen.dispose disposes the core) while a slow source is still
  // opening. Without it `firstWhere` throws a StateError, and since most loads
  // are launched unawaited that surfaces as an uncaught async error. Treat a
  // closed stream as a cancelled load (`false`).
  final settled = await core.stateStream
      .firstWhere(
        (s) => superseded(s) || isError(s) || isPlaybackOpen(s),
        orElse: () => core.state,
      )
      .timeout(timeout, onTimeout: () => core.state);

  if (superseded(settled) || isError(settled)) return false;
  if (isPlaybackOpen(settled)) return true;
  // Timed out without a confirmed open. Trust a `paused` source — a valid live
  // stream sits `paused` with no duration until the user plays it. Trust a
  // `playing` source only if its position has advanced past zero: that is real
  // evidence frames are flowing. A `playing` source still at position zero is the
  // premature-play case — the user pressed Space while a slow/bad source was
  // still opening, and media_kit reported `playing` with no duration before the
  // open succeeded or errored, so it is NOT evidence the source is good. Anything
  // still `loading`/`idle` never opened either.
  return settled.status == PlaybackStatus.paused ||
      (settled.status == PlaybackStatus.playing &&
          settled.position > Duration.zero);
}
