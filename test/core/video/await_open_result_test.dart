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

  /// A genuine open: paused with a known duration.
  void emitOpened() => emit(state.copyWith(
        status: PlaybackStatus.paused,
        duration: const Duration(minutes: 30),
      ));

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

  setUp(() => core = _ManualVideoCore());
  tearDown(() => core.dispose());

  test('true once the source actually opens (paused + duration)', () async {
    await core.load('https://x.test/a.mp4');
    final result = awaitOpenResult(core);
    core.emitOpened();
    expect(await result, isTrue);
  });

  test('false when the source errors', () async {
    await core.load('https://x.test/dead.mp4');
    final result = awaitOpenResult(core);
    core.emitError();
    expect(await result, isFalse);
  });

  test('the immediate paused tick is NOT mistaken for an open; a later '
      'error still wins', () async {
    await core.load('https://x.test/dead.mp4');
    final result = awaitOpenResult(core);
    core.emitPausedTick(); // paused, no duration — must not settle as opened
    core.emitError(); // the real outcome
    expect(await result, isFalse);
  });

  test('returns immediately when already opened before the call', () async {
    await core.load('https://x.test/a.mp4');
    core.emitOpened();
    expect(await awaitOpenResult(core), isTrue);
  });

  test('a stuck/paused-only load resolves to true after the timeout', () async {
    await core.load('https://x.test/slow-live.m3u8');
    core.emitPausedTick(); // live stream: paused, never a duration, never errors
    expect(
      await awaitOpenResult(core, timeout: const Duration(milliseconds: 50)),
      isTrue,
    );
  });
}
