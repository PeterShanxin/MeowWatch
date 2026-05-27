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
}
