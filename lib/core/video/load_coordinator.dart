import 'dart:async';

import 'await_open_result.dart' show openConfirmTimeout;
import 'playback_state.dart';
import 'video_core.dart';

/// Start a backend load and race its outcome against the source-scoped
/// open/error state, returning `true` only on a confirmed open (#228).
///
/// **Why not just `await startLoad()` then watch the state?** On a hard
/// rejection, media_kit reports the failure on a *separate* error stream — which
/// sets the error state and surfaces the recovery screen — while the
/// `Player.open`/`play` Futures behind [startLoad] can stay **pending forever**
/// (libmpv never sends the command reply for a source that failed to open). A
/// coordinator that awaited [startLoad] before watching the state would suspend
/// on that pending Future and never observe the error, so the caller's
/// retry/fallback logic never runs — the exact bug where a rejected YouTube link
/// left the user to click "Try again" by hand.
///
/// So [startLoad] is kicked off but never awaited: the verdict comes purely from
/// the state stream. The abandoned Future is error-observed so that if it *does*
/// eventually settle with an error, it can't crash the zone.
///
/// **Only [source]'s own states count.** The backend may not emit this load's
/// `loading` state synchronously — `_beginLoad` first awaits any in-flight
/// leave-room reset — so at the instant we start watching, `core.state` can still
/// be the *previous* source (a fast room-switch-then-load). We must not read that
/// as a supersede and bail before our load has even begun. So states whose
/// `filePath` is not [source] are ignored until [source] has appeared at least
/// once; only a *different* source appearing **after** ours is a genuine
/// supersede.
Future<bool> coordinateOpen(
  VideoCore core, {
  required String source,
  required Future<void> Function() startLoad,
  Duration timeout = openConfirmTimeout,
}) {
  final completer = Completer<bool>();
  StreamSubscription<PlaybackState>? sub;
  Timer? timer;
  var sawSource = false;

  void finish(bool result) {
    if (completer.isCompleted) return;
    timer?.cancel();
    unawaited(sub?.cancel());
    completer.complete(result);
  }

  // Returns true once a verdict is reached. `loading` for our source is not a
  // verdict — we keep waiting for it to open, error, be superseded, or time out.
  void consider(PlaybackState s) {
    if (s.filePath == source) {
      sawSource = true;
      if (s.status == PlaybackStatus.error) {
        finish(false);
      } else if (isPlaybackOpen(s)) {
        finish(true);
      }
    } else if (sawSource) {
      // A different source took over after ours was live — a real supersede.
      finish(false);
    }
    // else: a pre-load state (our load hasn't emitted yet) — ignore it.
  }

  sub = core.stateStream.listen(
    consider,
    // Stream closed — the core was disposed (user left mid-load). Cancelled.
    onDone: () => finish(false),
  );
  timer = Timer(timeout, () => finish(false));

  // Kick off the backend load. Never block on it — see the doc comment.
  // `.catchError` adopts its eventual error so an abandoned, later-failing
  // attempt is not an unhandled exception.
  unawaited(startLoad().catchError((_) {}));

  // The backend's `_beginLoad` emits `loading` synchronously (no pending reset),
  // so `core.state` may already be our source; broadcast delivery of that same
  // event is async, so check it directly too — without this a source that opened
  // before the first stream tick would be missed.
  consider(core.state);

  return completer.future;
}
