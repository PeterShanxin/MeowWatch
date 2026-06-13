import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

class FakeVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      fileName: filePath,
      status: PlaybackStatus.paused,
      duration: const Duration(minutes: 30),
      position: Duration.zero,
    ));
  }

  @override
  Future<void> play() async {
    emit(state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    emit(state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    emit(state.copyWith(volume: volume));
  }

  @override
  Future<void> disposeBackend() async {}
}

/// A core whose [load] parks in `loading` (no async open), so [failLoad]'s
/// timeout-to-error transition can be exercised.
class LoadingVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: filePath,
      filePath: filePath,
    ));
  }

  /// Force a zero-duration `playing` state on the still-loading source, mimicking
  /// a peer heartbeat (or the user) applying play() before open() returned.
  void forcePlayWhileLoading() =>
      emit(state.copyWith(status: PlaybackStatus.playing));

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> disposeBackend() async {}
}

void main() {
  late FakeVideoCore core;

  setUp(() {
    core = FakeVideoCore();
  });

  tearDown(() async {
    await core.dispose();
  });

  test('initial state is idle', () {
    expect(core.state.status, PlaybackStatus.idle);
  });

  test('load() transitions to paused with file name', () async {
    await core.load('C:\\videos\\demo.mkv');
    expect(core.state.status, PlaybackStatus.paused);
    expect(core.state.fileName, 'C:\\videos\\demo.mkv');
  });

  test('play() and pause() update status', () async {
    await core.load('test.mkv');
    await core.play();
    expect(core.state.status, PlaybackStatus.playing);
    await core.pause();
    expect(core.state.status, PlaybackStatus.paused);
  });

  test('state stream emits on changes', () async {
    final states = <PlaybackState>[];
    final sub = core.stateStream.listen(states.add);
    await core.load('test.mkv');
    await core.play();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(states.length, greaterThanOrEqualTo(2));
    expect(states.last.status, PlaybackStatus.playing);
  });

  group('failLoad', () {
    test('marks a still-loading core as error with the message', () async {
      final c = LoadingVideoCore();
      await c.load('https://x.test/hang.mp4');
      expect(c.state.status, PlaybackStatus.loading);
      c.failLoad('timed out');
      expect(c.state.status, PlaybackStatus.error);
      expect(c.state.errorMessage, 'timed out');
      await c.dispose();
    });

    test('is a no-op once genuinely open (never clobbers a real state)',
        () async {
      // FakeVideoCore opens straight to paused *with* a duration (open).
      await core.load('demo.mkv');
      core.failLoad('nope');
      expect(core.state.status, PlaybackStatus.paused);
      expect(core.state.errorMessage, isNull);
    });

    test('fails a source forced to `playing` over a never-opened load', () async {
      final c = LoadingVideoCore();
      await c.load('https://x.test/hung.m3u8');
      c.forcePlayWhileLoading(); // peer/user play() before open() returned
      expect(c.state.status, PlaybackStatus.playing);
      expect(c.state.duration, Duration.zero);
      c.failLoad('timed out');
      expect(c.state.status, PlaybackStatus.error);
      expect(c.state.errorMessage, 'timed out');
      await c.dispose();
    });
  });
}
