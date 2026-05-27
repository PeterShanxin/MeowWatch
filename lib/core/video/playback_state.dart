import 'package:flutter/foundation.dart';

enum PlaybackStatus { idle, loading, playing, paused, ended, error }

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
    String? fileName,
    String? errorMessage,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      fileName: fileName ?? this.fileName,
      errorMessage: errorMessage ?? this.errorMessage,
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
