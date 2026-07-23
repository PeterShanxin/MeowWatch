import 'dart:async';

import 'await_open_result.dart';
import 'video_core.dart';

/// Start a backend load and race its outcome against the source-scoped
/// open/error state, returning `true` only on a confirmed open (#228).
///
/// **Why not just `await startLoad()` then [awaitOpenResult]?** On a hard
/// rejection, media_kit reports the failure on a *separate* error stream — which
/// sets the error state and surfaces the recovery screen — while the
/// `Player.open`/`play` Futures behind [startLoad] can stay **pending forever**
/// (libmpv never sends the command reply for a source that failed to open). A
/// coordinator that awaited [startLoad] before watching the state would suspend
/// on that pending Future and never observe the error, so the caller's
/// retry/fallback logic never runs — the exact bug where a rejected YouTube
/// link left the user to click "Try again" by hand.
///
/// So [startLoad] is kicked off but never awaited here: its synchronous prologue
/// (the backend's `_beginLoad` emitting `loading`) still runs before
/// [awaitOpenResult] subscribes, and from then on the open-or-error verdict
/// comes purely from the state stream. The abandoned Future is error-observed so
/// that if it *does* eventually settle with an error, it can't crash the zone.
Future<bool> coordinateOpen(
  VideoCore core, {
  required String source,
  required Future<void> Function() startLoad,
  Duration timeout = openConfirmTimeout,
}) {
  // Never block on the backend Future — see the doc comment. `.catchError`
  // adopts its eventual error so an abandoned, later-failing attempt is not an
  // unhandled exception.
  unawaited(startLoad().catchError((_) {}));
  return awaitOpenResult(core, source: source, timeout: timeout);
}
