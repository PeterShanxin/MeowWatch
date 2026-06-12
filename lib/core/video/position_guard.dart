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
/// A position is only valid when it falls within the media: at or before the
/// known [duration] (plus a small rounding tolerance). While the duration is
/// still unknown (`<= 0`, as right after a load resets it) only `0:00` is
/// valid, which rejects the previous file's lingering end position.
bool acceptPlayerPosition({
  required Duration incoming,
  required Duration duration,
}) {
  if (incoming <= Duration.zero) return true;
  if (duration <= Duration.zero) return false;
  return incoming <= duration + positionOverrunTolerance;
}
