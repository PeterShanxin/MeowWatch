import 'package:flutter/foundation.dart';

import 'playback_state.dart';

/// The slice of [PlaybackState] the playback bar actually displays: play/pause
/// icon (status), the MM:SS position label + slider fraction (position, whole
/// seconds), the total-duration label + slider max (duration), and the volume
/// control's level (volume).
///
/// mpv observes `playback-time` continuously, so the raw state stream is a
/// per-frame firehose while a video plays. The bar's visible output only
/// changes when the displayed second flips (or status/duration/volume change),
/// yet subscribing it to the raw stream rebuilt its whole subtree — gradient,
/// slider theme, time labels — on every tick (#196). Projecting to this view
/// and de-duplicating collapses that to ~1 rebuild/second, the same pattern as
/// [PlaybackScreenView] one level up (#181).
@immutable
class PlaybackBarView {
  const PlaybackBarView({
    required this.status,
    required this.positionSeconds,
    required this.duration,
    required this.volume,
  });

  /// Project the displayed fields out of a full playback state.
  factory PlaybackBarView.of(PlaybackState state) => PlaybackBarView(
        status: state.status,
        positionSeconds: state.position.inSeconds,
        duration: state.duration,
        volume: state.volume,
      );

  final PlaybackStatus status;

  /// Position quantized to the whole second the bar displays — sub-second
  /// churn compares equal and is dropped by `distinct()`.
  final int positionSeconds;

  final Duration duration;
  final double volume;

  /// The quantized position as a [Duration], for the time label and slider.
  Duration get position => Duration(seconds: positionSeconds);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackBarView &&
        other.status == status &&
        other.positionSeconds == positionSeconds &&
        other.duration == duration &&
        other.volume == volume;
  }

  @override
  int get hashCode => Object.hash(status, positionSeconds, duration, volume);
}
