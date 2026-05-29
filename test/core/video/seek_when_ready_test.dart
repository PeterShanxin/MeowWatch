import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/seek_when_ready.dart';
import 'package:meowwatch/core/video/video_core.dart';

class _FakeVideoCore extends VideoCore {
  Duration? seekedTo;

  @override
  Future<void> load(String filePath) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {
    seekedTo = position;
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> disposeBackend() async {}

  void push(PlaybackState s) => emit(s);
}

void main() {
  late _FakeVideoCore video;

  setUp(() => video = _FakeVideoCore());
  tearDown(() async => video.dispose());

  test('non-positive target is a no-op', () async {
    await seekWhenReady(video, Duration.zero);
    expect(video.seekedTo, isNull);
  });

  test('seeks immediately when duration is already known', () async {
    video.push(const PlaybackState(duration: Duration(minutes: 10)));
    await seekWhenReady(video, const Duration(minutes: 3));
    expect(video.seekedTo, const Duration(minutes: 3));
  });

  test('waits for the first non-zero duration before seeking', () async {
    // Duration unknown at call time (the media_kit race): the seek must not
    // fire until a state with a real duration arrives.
    final future = seekWhenReady(video, const Duration(minutes: 3));
    await Future<void>.delayed(Duration.zero);
    expect(video.seekedTo, isNull, reason: 'must not seek before duration');

    video.push(const PlaybackState(duration: Duration(minutes: 10)));
    await future;
    expect(video.seekedTo, const Duration(minutes: 3));
  });

  test('seeks anyway once the timeout elapses without a duration', () async {
    await seekWhenReady(
      video,
      const Duration(minutes: 3),
      timeout: const Duration(milliseconds: 20),
    );
    expect(video.seekedTo, const Duration(minutes: 3));
  });
}
