import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'playback_state.dart';
import 'video_core.dart';
import 'video_decode_config.dart';
import 'video_url.dart';

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

  /// Configure libmpv decode and sync properties. Reads [Platform.environment]
  /// once so both env lookups share the same snapshot.
  ///
  /// **hwdec:** defaults to hardware decoding — zero-copy `d3d11va` on Windows,
  /// `auto-safe` elsewhere. Set [forceSoftwareDecodeEnvVar] for
  /// two-instance-on-one-PC local testing. See [video_decode_config.dart].
  ///
  /// **video-sync:** defaults to `display-resample` — locks frame presentation
  /// to the monitor refresh rate, resampling audio slightly to maintain A/V
  /// lock. Reduces judder and dropped frames. Set [forceAudioSyncEnvVar] to
  /// revert to mpv's `audio` (audio-clock master) mode, e.g. for VRR monitors
  /// or sync debugging.
  void _configureDecoding() {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      final env = Platform.environment;
      unawaited(
        platform.setProperty(
          'hwdec',
          resolveHwdec(
            forceSoftware: forceSoftwareDecodeFromEnv(env),
            isWindows: Platform.isWindows,
          ),
        ),
      );
      unawaited(
        platform.setProperty(
          'video-sync',
          resolveVideoSync(forceAudioSync: forceAudioSyncFromEnv(env)),
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

  /// Load a local file path *or* a direct `http(s)` stream URL — mpv accepts
  /// both in the same `Media(...)` slot, so a URL needs no special engine path.
  /// [mediaSourceName] keeps the display/announce name a base filename for a
  /// file and the full link for a URL (the Syncplay convention).
  @override
  Future<void> load(String source) async {
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: mediaSourceName(source),
      filePath: source,
      position: Duration.zero,
      duration: Duration.zero,
      errorMessage: null,
    ));
    await _player.open(Media(source), play: false);
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
