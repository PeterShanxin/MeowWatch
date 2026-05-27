import 'dart:async';

import 'package:flutter/foundation.dart';

import 'playback_state.dart';

/// Abstract interface for video playback. Implementations may wrap libmpv,
/// a fake for tests, or any other backend.
abstract class VideoCore {
  VideoCore() : _state = const PlaybackState();

  PlaybackState _state;
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  PlaybackState get state => _state;
  Stream<PlaybackState> get stateStream => _controller.stream;

  /// Emit a new state. Implementations call this from their backend listeners.
  @protected
  void emit(PlaybackState next) {
    _state = next;
    _controller.add(next);
  }

  Future<void> load(String filePath);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();

  Future<void> togglePlay() async {
    if (state.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }
}
