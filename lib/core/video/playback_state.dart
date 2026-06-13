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
    this.filePath,
    this.errorMessage,
  });

  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double volume;
  final String? fileName;
  final String? filePath;
  final String? errorMessage;

  PlaybackState copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    double? volume,
    Object? fileName = _unset,
    Object? filePath = _unset,
    Object? errorMessage = _unset,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      fileName: identical(fileName, _unset) ? this.fileName : fileName as String?,
      filePath: identical(filePath, _unset) ? this.filePath : filePath as String?,
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
        other.filePath == filePath &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        status,
        position,
        duration,
        volume,
        fileName,
        filePath,
        errorMessage,
      );
}

/// Positive evidence that the source actually opened — not a hopeful state from
/// a source that's still loading. The load screen mounts a real video surface,
/// so a user can press Space while a slow source is still opening; media_kit may
/// then report `playing`/`paused` with a zero duration *before* the open
/// succeeds or errors. A genuine open reports a known (non-zero) duration, so we
/// require it for both `playing` and `paused`; only `ended` (the file ran to its
/// end) is accepted on its own. Used to gate announce / record / resume on a
/// confirmed open rather than a premature one.
bool isPlaybackOpen(PlaybackState state) {
  switch (state.status) {
    case PlaybackStatus.playing:
    case PlaybackStatus.paused:
      return state.duration > Duration.zero;
    case PlaybackStatus.ended:
      return true;
    case PlaybackStatus.idle:
    case PlaybackStatus.loading:
    case PlaybackStatus.error:
      return false;
  }
}
