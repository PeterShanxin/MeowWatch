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
  bool _disposed = false;

  PlaybackState get state => _state;
  Stream<PlaybackState> get stateStream => _controller.stream;

  /// Emit a new state. Implementations call this from their backend listeners.
  /// No-op after [dispose] to avoid late callbacks racing teardown.
  @protected
  void emit(PlaybackState next) {
    if (_disposed) return;
    _state = next;
    _controller.add(next);
  }

  Future<void> load(String filePath);

  /// Force the in-flight load into the error state with [message]. Used when a
  /// load hangs past a caller's timeout with no backend error, so the UI can
  /// show its recovery screen instead of a frozen loading surface. No-op unless
  /// still `loading`, so it can't clobber a real opened/errored state.
  void failLoad(String message) {
    if (_state.status != PlaybackStatus.loading) return;
    emit(_state.copyWith(
      status: PlaybackStatus.error,
      errorMessage: message,
    ));
  }

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  /// Tear down backend resources. Subclasses override this; the base
  /// [dispose] closes the state stream.
  @protected
  Future<void> disposeBackend();

  /// Final teardown. Closes the state stream after backend cleanup.
  @mustCallSuper
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disposeBackend();
    await _controller.close();
  }

  Future<void> togglePlay() async {
    if (state.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }
}
