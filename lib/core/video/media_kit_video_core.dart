import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'playback_state.dart';
import 'position_guard.dart';
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

  /// `false` from a [load] until playback is actually started or deliberately
  /// positioned ([play]/[seek]). While `false`, a freshly loaded file sits at
  /// 0:00 (we open with `play: false`), so non-zero positions in this window
  /// are stale ticks from the previous file and must be dropped (#132).
  bool _playbackStarted = false;

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
        // Reject a stale end-of-file position from the previous file that
        // libmpv can deliver mid-load — otherwise a freshly loaded episode
        // shows the old one's end instead of 0:00, and a room would broadcast
        // the wrong position (#132). See [acceptPlayerPosition].
        if (!acceptPlayerPosition(
          incoming: pos,
          duration: state.duration,
          started: _playbackStarted,
        )) {
          return;
        }
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
    // Arm the stale-position guard: until the user plays or seeks, the new file
    // legitimately sits at 0:00 and any non-zero tick is the previous file's
    // lingering end position (#132).
    _playbackStarted = false;
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
  Future<void> play() {
    _playbackStarted = true;
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) {
    _playbackStarted = true;
    return _player.seek(position);
  }

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
