import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/await_open_result.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// A core whose [load] only enters `loading`; the test drives the outcome by
/// emitting a later state, mimicking mpv's async open success/failure.
class _ManualVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: filePath,
      filePath: filePath,
    ));
  }

  void settlePaused() => emit(state.copyWith(status: PlaybackStatus.paused));
  void settleError() => emit(state.copyWith(
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

  test('returns true when the source opens (settles to paused)', () async {
    await core.load('https://x.test/a.mp4');
    final result = awaitOpenResult(core);
    core.settlePaused();
    expect(await result, isTrue);
  });

  test('returns false when the source errors', () async {
    await core.load('https://x.test/dead.mp4');
    final result = awaitOpenResult(core);
    core.settleError();
    expect(await result, isFalse);
  });

  test('returns immediately when already settled before the call', () async {
    await core.load('https://x.test/a.mp4');
    core.settlePaused();
    expect(await awaitOpenResult(core), isTrue);
  });

  test('a stuck load resolves to true after the timeout (optimistic)',
      () async {
    await core.load('https://x.test/slow-live.m3u8');
    expect(
      await awaitOpenResult(core, timeout: const Duration(milliseconds: 50)),
      isTrue,
    );
  });
}
