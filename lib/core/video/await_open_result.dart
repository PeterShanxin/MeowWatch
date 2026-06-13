import 'dart:async';

import 'playback_state.dart';
import 'video_core.dart';

/// Wait for a just-issued [VideoCore.load] of [source] to either open or fail,
/// returning `true` on success and `false` on error/supersede/hang.
///
/// mpv reports a bad source (an unreachable / non-video / expired link, or a
/// moved / unreadable local file) on its error stream *after* `load()` has
/// returned, and media_kit emits a `paused` tick the instant `open()` returns —
/// before that error. So we never settle on the bare paused tick: we wait for a
/// confirmed open ([isPlaybackOpen]), an error, or the timeout.
///
/// The wait is scoped to [source]: once `filePath` no longer matches (a newer
/// load superseded this one), we stop and return `false` — the newer load owns
/// the core state and reports its own outcome. This keeps a stale/slow load from
/// consuming a state, error, or open that now belongs to a different source.
///
/// On [timeout] we accept only if `open()` actually returned for this source at
/// some point — i.e. it reached `paused`/`ended` or an [isPlaybackOpen] state.
/// That is the only thing that distinguishes a valid live/direct stream (which
/// sits `paused` with no duration, position pinned at 0) from a source that
/// never opened. A bare zero-duration `playing` is NOT open evidence: a peer
/// heartbeat (or the user) can force `play()` onto a still-`loading` source whose
/// `open()` never returned (a hung URL), so a source that jumped straight from
/// `loading` to `playing` without a `paused` tick is treated as a hang → `false`.
Future<bool> awaitOpenResult(
  VideoCore core, {
  required String source,
  Duration timeout = const Duration(seconds: 12),
}) async {
  bool superseded(PlaybackState s) => s.filePath != source;
  bool isError(PlaybackState s) => s.status == PlaybackStatus.error;
  // Evidence that `open()` returned for this source: media_kit emits a `paused`
  // tick the instant it does (a bad source emits it too, then errors). `ended`
  // and any `isPlaybackOpen` state count as well. A bare `playing` does not —
  // that can be a forced play over a never-opened source.
  bool isOpenEvidence(PlaybackState s) =>
      !superseded(s) &&
      (s.status == PlaybackStatus.paused ||
          s.status == PlaybackStatus.ended ||
          isPlaybackOpen(s));

  // Already settled before we looked (the event arrived before we subscribed).
  if (superseded(core.state) || isError(core.state)) return false;
  if (isPlaybackOpen(core.state)) return true;

  var sawOpen = isOpenEvidence(core.state);
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
      } else if (isOpenEvidence(s)) {
        // Reached `paused`/`ended` with no duration (a live/direct stream).
        // Keep waiting in case an error follows, but remember it opened.
        sawOpen = true;
      }
    },
    // Stream closed — the core was disposed (e.g. the user left/closed the room
    // mid-load). Treat it as a cancelled load. Without this the underlying
    // future would never complete.
    onDone: () => finish(false),
  );

  // On timeout, trust the source only if `open()` actually returned for it (a
  // slow-but-good live stream). A hang — still `loading`, or force-played to
  // `playing` without ever opening — never produced that evidence → `false`.
  timer = Timer(timeout, () => finish(sawOpen));

  return completer.future;
}
