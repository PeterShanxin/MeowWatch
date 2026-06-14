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

  /// True once [dispose] has run (the state stream is closed). Lets callers that
  /// await the stream avoid acting on a torn-down core (e.g. seeking after the
  /// user left the room mid-load).
  bool get isDisposed => _disposed;

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
  /// show its recovery screen instead of a frozen loading surface. No-op once the
  /// source is genuinely open (a real duration / `ended`) or already errored, so
  /// it can't clobber a real state.
  void failLoad(String message) {
    // Never clobber a confirmed open (a real duration / `ended`) or an existing
    // error. Otherwise force the in-flight load into error: the usual `loading`
    // hang, but also a `playing`/`paused` state forced onto a source whose
    // `open()` never returned (e.g. a peer heartbeat applying play() over a hung
    // URL), which still carries no duration. Without this the user would be stuck
    // on a frozen surface with no recovery buttons.
    if (isPlaybackOpen(_state) || _state.status == PlaybackStatus.error) return;
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
