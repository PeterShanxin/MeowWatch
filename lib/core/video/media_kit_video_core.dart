import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'playback_state.dart';
import 'video_core.dart';
import 'video_decode_config.dart';

class MediaKitVideoCore extends VideoCore {
  MediaKitVideoCore() : _player = Player() {
    // Create the render controller up front, BEFORE any media is opened. If it
    // is attached lazily (only once a VideoSurface mounts, i.e. after the first
    // open()), libmpv has no video output wired for that first file and it never
    // starts — which looked like "the first video won't play, but reloading a
    // new one works". Eager creation is also media_kit's documented pattern.
    videoController = VideoController(_player);
    _wireListeners();
    _configureDecoding();
  }

  final Player _player;
  late final VideoController videoController;
  late final List<StreamSubscription<Object?>> _subs;

  Player get player => _player;

  /// Configure the libmpv `hwdec` property. Defaults to hardware decoding —
  /// zero-copy `d3d11va` on Windows, `auto-safe` elsewhere — a big
  /// CPU/battery/heat win on Snapdragon X / Adreno and other GPUs, with
  /// automatic software fallback where HW decode is unavailable. Set
  /// [forceSoftwareDecodeEnvVar] to force software decode for
  /// two-instance-on-one-PC local testing (the two instances would otherwise
  /// contend for the single hardware decoder session and the second would stall
  /// at frame 0). See [video_decode_config.dart] for the full rationale.
  void _configureDecoding() {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      final forceSoftware = forceSoftwareDecodeFromEnv(Platform.environment);
      unawaited(
        platform.setProperty(
          'hwdec',
          resolveHwdec(
            forceSoftware: forceSoftware,
            isWindows: Platform.isWindows,
          ),
        ),
      );
    }
  }

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
      filePath: filePath,
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
