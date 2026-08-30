import 'dart:async';

import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// A [VideoCore] fake that behaves like a real player for sync tests: it
/// advances its position on a wall-clock ticker while playing, so the bridge's
/// seek detection, drift comparison and stalled-resume watchdog all see the
/// same shape of stream a live media_kit engine produces.
///
/// Used by the two-client Local -> Synced integration tests, where a
/// non-advancing fake would look like a frozen engine to [PeerStallTracker].
class ScriptedVideoCore extends VideoCore {
  ScriptedVideoCore({this.tick = const Duration(milliseconds: 25)});

  /// How often a playing source emits a position tick.
  final Duration tick;

  /// Every backend command the bridge issued, in order.
  final List<String> commands = <String>[];

  Timer? _ticker;
  DateTime _lastAdvance = DateTime.now();

  /// Open [path] at [at], already confirmed open (real duration), paused.
  void openAt(
    String path, {
    Duration at = Duration.zero,
    Duration duration = const Duration(hours: 2),
    bool playing = false,
  }) {
    emit(
      PlaybackState(
        status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        position: at,
        duration: duration,
        fileName: path,
        filePath: path,
        opened: true,
      ),
    );
    _syncTicker();
  }

  @override
  Future<void> load(String filePath) async {
    commands.add('load:$filePath');
    openAt(filePath);
  }

  @override
  Future<void> play() async {
    commands.add('play');
    emit(state.copyWith(status: PlaybackStatus.playing));
    _syncTicker();
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    emit(state.copyWith(status: PlaybackStatus.paused));
    _syncTicker();
  }

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inMilliseconds}ms');
    _lastAdvance = DateTime.now();
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async =>
      emit(state.copyWith(volume: volume));

  /// A local user pressing play/pause/seek (no bridge involvement).
  void userPlay() => unawaited(play());
  void userPause() => unawaited(pause());
  void userSeek(Duration to) => unawaited(seek(to));

  void _syncTicker() {
    final playing = state.status == PlaybackStatus.playing;
    if (playing && _ticker == null) {
      _lastAdvance = DateTime.now();
      _ticker = Timer.periodic(tick, (_) => _advance());
    } else if (!playing) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _advance() {
    if (isDisposed || state.status != PlaybackStatus.playing) return;
    final now = DateTime.now();
    final delta = now.difference(_lastAdvance);
    _lastAdvance = now;
    emit(state.copyWith(position: state.position + delta));
  }

  @override
  Future<void> disposeBackend() async {
    _ticker?.cancel();
    _ticker = null;
  }
}
