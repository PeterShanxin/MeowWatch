import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/seek_when_ready.dart';
import 'package:meowwatch/core/video/video_core.dart';

class _FakeVideoCore extends VideoCore {
  Duration? seekedTo;
  int seekCalls = 0;
  int dropSeekCount = 0;

  @override
  Future<void> load(String filePath) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    if (dropSeekCount > 0) {
      dropSeekCount--;
      return;
    }
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

  test('a closed stream mid-wait does not throw and does not seek', () async {
    final future = seekWhenReady(video, const Duration(minutes: 3));
    await Future<void>.delayed(Duration.zero);
    await video.dispose(); // closes the stream before a duration arrives
    await future; // must complete without a StateError
    expect(video.seekedTo, isNull);
  });

  test('a superseded source (filePath changed) skips the seek', () async {
    video.push(const PlaybackState(filePath: 'a.mp4'));
    final future = seekWhenReady(
      video,
      const Duration(minutes: 3),
      source: 'a.mp4',
    );
    await Future<void>.delayed(Duration.zero);
    // A newer load swaps the source before a duration for 'a.mp4' arrives.
    video.push(const PlaybackState(filePath: 'b.mp4'));
    await future;
    expect(video.seekedTo, isNull);
  });

  test('seeks the resumed source once its duration arrives (scoped)', () async {
    video.push(const PlaybackState(filePath: 'a.mp4'));
    final future = seekWhenReady(
      video,
      const Duration(minutes: 3),
      source: 'a.mp4',
    );
    await Future<void>.delayed(Duration.zero);
    video.push(
      const PlaybackState(filePath: 'a.mp4', duration: Duration(minutes: 10)),
    );
    await future;
    expect(video.seekedTo, const Duration(minutes: 3));
  });

  test('retries a resume seek that the paused backend does not land', () async {
    video.push(
      const PlaybackState(filePath: 'a.mp4', duration: Duration(minutes: 10)),
    );
    video.dropSeekCount = 1;

    await seekWhenReady(
      video,
      const Duration(minutes: 3),
      source: 'a.mp4',
      retryDelay: const Duration(milliseconds: 1),
    );

    expect(video.seekCalls, 2);
    expect(video.state.position, const Duration(minutes: 3));
  });
}
