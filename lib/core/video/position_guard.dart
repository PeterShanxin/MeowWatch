/// Tolerance for an end-of-file position that rounds a hair past the reported
/// duration — libmpv can report e.g. 120.001s for a 120.000s file, and we don't
/// want to drop that legitimate final tick.
const Duration positionOverrunTolerance = Duration(seconds: 1);

/// Whether an incoming player position is valid for the current media.
///
/// libmpv's event loop can deliver a final end-of-file `time-pos` from the
/// *previous* file just after we begin loading the next one. Because we load
/// with `play: false`, the new file never re-ticks its position back down, so
/// that stale end value would stick and the seek bar would show the old
/// episode's end instead of `0:00` — and in a room it would broadcast/follow
/// the wrong position (issue #132).
///
/// [started] is `false` from the moment a file is loaded until playback is
/// actually started or deliberately positioned (a `play()` or `seek()`). In
/// that window the freshly loaded file sits at `0:00` with `play: false`, so
/// any non-zero position is necessarily a stale tick from the *previous* file
/// — reject it regardless of how long the new file is. (Without this, a stale
/// end like `23:55` would slip through whenever the next episode is at least
/// as long, e.g. `24:10`, because it still fits within the new duration.)
///
/// Once playback has started, the only remaining guard is the sanity invariant
/// that a position never exceeds the media's [duration] (plus a small rounding
/// tolerance for an end-of-file tick that lands a hair past it).
///
/// [probeZeroPending] identifies the one delayed `0:00` event produced by the
/// paused-load decode probe. If an explicit non-zero seek has already moved the
/// player away from zero, that stale probe event must not undo the seek. A
/// normal zero remains valid when no probe event is pending.
bool acceptPlayerPosition({
  required Duration incoming,
  required Duration duration,
  required bool started,
  Duration current = Duration.zero,
  bool probeZeroPending = false,
}) {
  if (incoming <= Duration.zero) {
    return !(probeZeroPending && started && current > Duration.zero);
  }
  if (!started) return false;
  if (duration <= Duration.zero) return false;
  return incoming <= duration + positionOverrunTolerance;
}
