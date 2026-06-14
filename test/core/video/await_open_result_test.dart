import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/await_open_result.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// A core whose [load] only enters `loading`; the test drives the outcome by
/// emitting later states, mimicking mpv's async open success/failure.
class _ManualVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: filePath,
      filePath: filePath,
      duration: Duration.zero,
    ));
  }

  /// The immediate post-open tick: paused but no duration yet. NOT a confirmed
  /// open — a failing source emits this too, then errors.
  void emitPausedTick() => emit(state.copyWith(status: PlaybackStatus.paused));

  /// A genuine VOD open: paused with a known duration.
  void emitOpened() => emit(state.copyWith(
        status: PlaybackStatus.paused,
        duration: const Duration(minutes: 30),
      ));

  /// A genuine durationless open (a live/direct stream): the backend confirmed
  /// the source opened via the `opened` flag, but there is no duration.
  void emitOpenedLive() => emit(state.copyWith(
        status: PlaybackStatus.paused,
        opened: true,
      ));

  /// The user pressing play over a still-opening source: `playing`, no duration,
  /// no `opened` flag (the source never demuxed). Not open evidence.
  void emitPrematurePlay() =>
      emit(state.copyWith(status: PlaybackStatus.playing));

  void emitError() => emit(state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: 'boom',
      ));

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
  late _ManualVideoCore core;
  const src = 'https://x.test/a.mp4';

  setUp(() => core = _ManualVideoCore());
  tearDown(() => core.dispose());

  test('true once the source actually opens (paused + duration)', () async {
    await core.load(src);
    final result = awaitOpenResult(core, source: src);
    core.emitOpened();
    expect(await result, isTrue);
  });

  test('false when the source errors', () async {
    await core.load('https://x.test/dead.mp4');
    final result = awaitOpenResult(core, source: 'https://x.test/dead.mp4');
    core.emitError();
    expect(await result, isFalse);
  });

  test('the immediate paused tick is NOT mistaken for an open; a later '
      'error still wins', () async {
    await core.load('https://x.test/dead.mp4');
    final result = awaitOpenResult(core, source: 'https://x.test/dead.mp4');
    core.emitPausedTick(); // paused, no duration — must not settle as opened
    core.emitError(); // the real outcome
    expect(await result, isFalse);
  });

  test('returns immediately when already opened before the call', () async {
    await core.load(src);
    core.emitOpened();
    expect(await awaitOpenResult(core, source: src), isTrue);
  });

  test('a durationless live stream resolves to true once the backend confirms '
      'the open (no duration needed)', () async {
    await core.load('https://x.test/live.m3u8');
    final result = awaitOpenResult(
      core,
      source: 'https://x.test/live.m3u8',
      timeout: const Duration(milliseconds: 50),
    );
    core.emitOpenedLive(); // demuxer params arrived → opened flag set
    expect(await result, isTrue);
  });

  test('a confirmed-open live stream the user then plays stays true', () async {
    await core.load('https://x.test/live.m3u8');
    final result = awaitOpenResult(core, source: 'https://x.test/live.m3u8');
    core.emitOpenedLive(); // opens (params) …
    core.emitPrematurePlay(); // … then the user presses Space
    expect(await result, isTrue);
  });

  test('a source forced to `playing` without ever opening resolves to false at '
      'the timeout', () async {
    await core.load('https://x.test/hung.m3u8');
    // A peer heartbeat applied play() over the still-loading source: `playing`
    // with no duration and no `opened` flag — not open evidence.
    core.emitPrematurePlay();
    expect(
      await awaitOpenResult(
        core,
        source: 'https://x.test/hung.m3u8',
        timeout: const Duration(milliseconds: 50),
      ),
      isFalse,
    );
  });

  test('a source forced to `paused` without ever opening resolves to false at '
      'the timeout', () async {
    await core.load('https://x.test/hung.m3u8');
    // The user pressed Space twice (play then pause), forging a zero-duration
    // `paused` tick over a source whose open() never returned — not open
    // evidence, so it must not be accepted.
    core.emitPrematurePlay();
    core.emitPausedTick();
    expect(
      await awaitOpenResult(
        core,
        source: 'https://x.test/hung.m3u8',
        timeout: const Duration(milliseconds: 50),
      ),
      isFalse,
    );
  });

  test('a played-but-never-opened source that then errors resolves to false',
      () async {
    await core.load('https://x.test/dead.mp4');
    final result = awaitOpenResult(core, source: 'https://x.test/dead.mp4');
    core.emitPausedTick(); // the pre-error paused tick…
    core.emitPrematurePlay(); // …user played over it…
    core.emitError(); // …but it never truly opened and then errors
    expect(await result, isFalse);
  });

  test('a still-loading hang resolves to false after the timeout', () async {
    await core.load('https://x.test/never-responds.mp4');
    // No tick at all — open() never returned a playable state. A timeout here
    // must NOT be treated as a successful load.
    expect(
      await awaitOpenResult(
        core,
        source: 'https://x.test/never-responds.mp4',
        timeout: const Duration(milliseconds: 50),
      ),
      isFalse,
    );
  });

  test('a superseding load (filePath changes) resolves the old wait to false',
      () async {
    await core.load(src);
    final result = awaitOpenResult(core, source: src);
    // A newer load takes over the shared core: filePath no longer matches src.
    await core.load('https://x.test/b.mp4');
    expect(await result, isFalse);
  });

  test("a superseded source's later open does not count for the old wait",
      () async {
    await core.load(src);
    final result = awaitOpenResult(core, source: src);
    await core.load('https://x.test/b.mp4'); // supersede
    core.emitOpened(); // this open belongs to b, not src
    expect(await result, isFalse);
  });

  test('a closed stream (leave/dispose mid-load) resolves to false, not throw',
      () async {
    final c = _ManualVideoCore();
    await c.load(src);
    final result = awaitOpenResult(c, source: src);
    await c.dispose(); // closes the state stream while still loading
    expect(await result, isFalse);
  });
}
