import 'package:flutter/foundation.dart';

/// The outcome of feeding one `duration` event through [evaluateDurationEvent].
@immutable
class DurationGateResult {
  const DurationGateResult({required this.resetSeen, required this.accept});

  /// The per-load "reset seen" latch to carry into the next event. Arms (`true`)
  /// the first time this load's `duration:0` boundary crosses the stream.
  final bool resetSeen;

  /// Whether this duration should be applied to `PlaybackState` as the current
  /// source's duration (and so counted as open evidence).
  final bool accept;

  @override
  bool operator ==(Object other) =>
      other is DurationGateResult &&
      other.resetSeen == resetSeen &&
      other.accept == accept;

  @override
  int get hashCode => Object.hash(resetSeen, accept);
}

/// Decide whether an incoming `duration` event belongs to the CURRENT load.
///
/// media_kit emits `duration: 0` inside `Player.open`'s `stop(open: true)` —
/// always, before the demuxer reads the new container — so the first zero on the
/// duration stream is this load's START_FILE boundary. A non-zero duration AFTER
/// it is the current source's; a late non-zero from the source we just unloaded
/// (a reused engine can deliver one while the next load is in flight — #137/#143)
/// arrives BEFORE that zero on the same stream (FIFO) and is dropped, so it can't
/// falsely mark the new source open.
///
/// Gating on the duration stream's OWN reset — not the videoParams reset — is
/// deliberate. Duration and videoParams are separate streams, and on a warm
/// reused engine the real container duration can overtake the empty videoParams
/// marker. Gating duration on that cross-stream marker dropped a genuine
/// duration, leaving a PAUSED load (whose video params don't decode until play)
/// with no open evidence at all → a false 12s "Timed out waiting for the video to
/// open" on a perfectly good file when switching episodes.
///
/// [resetSeen] is the latch carried from this load's previous event; start each
/// load with `false`. Returns the next latch value and whether to apply [incoming].
DurationGateResult evaluateDurationEvent({
  required bool resetSeen,
  required Duration incoming,
}) {
  if (incoming <= Duration.zero) {
    // The START_FILE reset (or a durationless/live source sitting at zero): arm
    // the latch, but a zero is never itself open evidence.
    return const DurationGateResult(resetSeen: true, accept: false);
  }
  return DurationGateResult(resetSeen: resetSeen, accept: resetSeen);
}
