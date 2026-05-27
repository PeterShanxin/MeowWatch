import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'playback_state.dart';
import 'video_core.dart';

class MediaKitVideoCore extends VideoCore {
  MediaKitVideoCore() : _player = Player() {
    _wireListeners();
  }

  final Player _player;
  late final List<StreamSubscription<Object?>> _subs;

  Player get player => _player;

  void _wireListeners() {
    _subs = [
      _player.stream.playing.listen((playing) {
        emit(state.copyWith(
          status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        ));
      }),
      _player.stream.position.listen((pos) {
        emit(state.copyWith(position: pos));
      }),
      _player.stream.duration.listen((dur) {
        emit(state.copyWith(duration: dur));
      }),
      _player.stream.volume.listen((vol) {
        emit(state.copyWith(volume: vol / 100.0));
      }),
      _player.stream.completed.listen((done) {
        if (done) emit(state.copyWith(status: PlaybackStatus.ended));
      }),
      _player.stream.error.listen((err) {
        emit(state.copyWith(
          status: PlaybackStatus.error,
          errorMessage: err.toString(),
        ));
      }),
    ];
  }

  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: p.basename(filePath),
      position: Duration.zero,
      duration: Duration.zero,
      errorMessage: null,
    ));
    await _player.open(Media(filePath), play: false);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume((volume.clamp(0.0, 1.0)) * 100.0);

  @override
  Future<void> disposeBackend() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }
}
