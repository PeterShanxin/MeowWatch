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
    this.opened = false,
  });

  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double volume;
  final String? fileName;
  final String? filePath;
  final String? errorMessage;

  /// `true` once the backend has confirmed the current source genuinely opened —
  /// its demuxer read real audio/video params. Unlike `playing`/`paused` (which a
  /// user Space-press or a peer heartbeat can force onto a still-loading source)
  /// or a `duration` (which a live/direct stream never reports), this can't be
  /// faked from outside the player, so it's the authoritative open signal for a
  /// durationless live stream. Reset to `false` at the start of each [load].
  final bool opened;

  PlaybackState copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    double? volume,
    Object? fileName = _unset,
    Object? filePath = _unset,
    Object? errorMessage = _unset,
    bool? opened,
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
      opened: opened ?? this.opened,
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
        other.errorMessage == errorMessage &&
        other.opened == opened;
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
        opened,
      );
}

/// Positive evidence that the source actually opened — not a hopeful state from
/// a source that's still loading. The load screen mounts a real video surface,
/// so a user can press Space (or a peer heartbeat can apply play/pause) while a
/// slow source is still opening; media_kit then reports `playing`/`paused` with a
/// zero duration *before* the open succeeds or errors. Neither that status nor
/// the bare position can be trusted, so we require unforgeable evidence: either a
/// known (non-zero) `duration` (a VOD reports it on open; it can't be faked from
/// outside the player) or the backend's [PlaybackState.opened] flag (set from the
/// demuxer's real audio/video params — the only open signal a durationless
/// live/direct stream gives). `ended` (the file ran to its end) is accepted on
/// its own. Used to gate announce / record / resume on a confirmed open.
bool isPlaybackOpen(PlaybackState state) {
  switch (state.status) {
    case PlaybackStatus.playing:
    case PlaybackStatus.paused:
      return state.opened || state.duration > Duration.zero;
    case PlaybackStatus.ended:
      return true;
    case PlaybackStatus.idle:
    case PlaybackStatus.loading:
    case PlaybackStatus.error:
      return false;
  }
}
