import 'package:flutter/foundation.dart';

enum PlaybackStatus { idle, loading, playing, paused, ended, error }

/// Sentinel used by [PlaybackState.copyWith] so callers can distinguish
/// "leave field unchanged" (omit) from "clear field" (pass `null` explicitly).
const Object _unset = Object();

@immutable
class PlaybackState {
  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.fileName,
    this.errorMessage,
  });

  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double volume;
  final String? fileName;
  final String? errorMessage;

  PlaybackState copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    double? volume,
    Object? fileName = _unset,
    Object? errorMessage = _unset,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      fileName: identical(fileName, _unset) ? this.fileName : fileName as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackState &&
        other.status == status &&
        other.position == position &&
        other.duration == duration &&
        other.volume == volume &&
        other.fileName == fileName &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        status,
        position,
        duration,
        volume,
        fileName,
        errorMessage,
      );
}
