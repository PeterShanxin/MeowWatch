import 'dart:async';

import 'playback_state.dart';
import 'video_core.dart';

/// How long we wait for a just-issued load to confirm it opened before treating
/// it as a hang. Shared so the in-core decode probe
/// ([MediaKitVideoCore] `_forceDecodeToConfirmOpen`) and this coordinator wait
/// use the SAME budget rather than two stacked timeouts — a genuinely stuck
/// source fails at ~this duration, not double it.
const Duration openConfirmTimeout = Duration(seconds: 12);

/// Wait for a just-issued [VideoCore.load] of [source] to either open or fail,
/// returning `true` on a confirmed open and `false` on error/supersede/timeout.
///
/// "Open" is [isPlaybackOpen]: a real (non-zero) duration, the backend's
/// unforgeable [PlaybackState.opened] flag (set from the demuxer's real
/// audio/video params — the only open signal a durationless live/direct stream
/// gives), or `ended`. We deliberately do NOT treat a bare `paused`/`playing`
/// tick as open: the load screen mounts a real video surface, so a user
/// Space-press — or a peer heartbeat applying play/pause — can force either
/// status onto a still-`loading`, never-opened source (e.g. a hung URL), and mpv
/// also emits a `paused` tick the instant a *bad* source's `open()` returns,
/// right before its error. So we wait for that confirmed-open evidence, an error,
/// or the timeout.
///
/// The wait is scoped to [source]: once `filePath` no longer matches (a newer
/// load superseded this one), we stop and return `false` — the newer load owns
/// the core state and reports its own outcome. This keeps a stale/slow load from
/// consuming a state, error, or open that now belongs to a different source.
///
/// On [timeout] (or if the stream closes first, e.g. the user leaves the room
/// mid-load) we return `false`: a source that never produced confirmed-open
/// evidence within this generous window never opened — a hang.
Future<bool> awaitOpenResult(
  VideoCore core, {
  required String source,
  Duration timeout = openConfirmTimeout,
}) async {
  bool superseded(PlaybackState s) => s.filePath != source;
  bool isError(PlaybackState s) => s.status == PlaybackStatus.error;

  // Already settled before we looked (the event arrived before we subscribed).
  if (superseded(core.state) || isError(core.state)) return false;
  if (isPlaybackOpen(core.state)) return true;

  final completer = Completer<bool>();
  StreamSubscription<PlaybackState>? sub;
  Timer? timer;

  void finish(bool result) {
    if (completer.isCompleted) return;
    timer?.cancel();
    unawaited(sub?.cancel());
    completer.complete(result);
  }

  sub = core.stateStream.listen(
    (s) {
      if (superseded(s) || isError(s)) {
        finish(false);
      } else if (isPlaybackOpen(s)) {
        finish(true);
      }
    },
    // Stream closed — the core was disposed (e.g. the user left/closed the room
    // mid-load). Treat it as a cancelled load. Without this the future would
    // never complete.
    onDone: () => finish(false),
  );

  // Never confirmed open within the window → a hang (or a forced play/pause over
  // a source that never opened).
  timer = Timer(timeout, () => finish(false));

  return completer.future;
}
