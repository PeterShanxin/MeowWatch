import 'package:flutter/material.dart';

/// A discrete playback action the user triggered, used to flash a transient
/// feedback icon over the video (play, pause, seek, volume).
enum PlaybackAction {
  play,
  pause,
  seekForward,
  seekBackward,
  volumeUp,
  volumeDown,
}

IconData iconForAction(PlaybackAction action) {
  switch (action) {
    case PlaybackAction.play:
      return Icons.play_arrow_rounded;
    case PlaybackAction.pause:
      return Icons.pause_rounded;
    case PlaybackAction.seekForward:
      return Icons.forward_5_rounded;
    case PlaybackAction.seekBackward:
      return Icons.replay_5_rounded;
    case PlaybackAction.volumeUp:
      return Icons.volume_up_rounded;
    case PlaybackAction.volumeDown:
      return Icons.volume_down_rounded;
  }
}
