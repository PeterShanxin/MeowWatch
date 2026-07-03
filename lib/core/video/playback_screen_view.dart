import 'package:flutter/foundation.dart';

import 'playback_state.dart';

/// The coarse, position-free slice of [PlaybackState] that screen-level UI
/// (the room screen's body Stack) actually consumes: which surface to show
/// (empty / error / video) and what to label it with.
///
/// mpv observes `playback-time` continuously, so the raw state stream is a
/// per-frame firehose while a video plays. Screen-level UI that rebuilt on the
/// raw stream re-ran its whole subtree on every tick for the whole watch
/// session (#181). Projecting to this view and de-duplicating means position
/// (and duration/volume) churn never reaches it; widgets that genuinely need
/// position (playback bar, video surface) keep their own scoped subscriptions
/// to the raw stream.
@immutable
class PlaybackScreenView {
  const PlaybackScreenView({
    required this.status,
    required this.fileName,
    required this.filePath,
    required this.errorMessage,
  });

  /// Project the coarse fields out of a full playback state.
  factory PlaybackScreenView.of(PlaybackState state) => PlaybackScreenView(
        status: state.status,
        fileName: state.fileName,
        filePath: state.filePath,
        errorMessage: state.errorMessage,
      );

  final PlaybackStatus status;
  final String? fileName;
  final String? filePath;
  final String? errorMessage;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackScreenView &&
        other.status == status &&
        other.fileName == fileName &&
        other.filePath == filePath &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(status, fileName, filePath, errorMessage);
}
