import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/load_coordinator.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// A core that only ever enters `loading` on [load]; tests drive the rest by
/// emitting later states, exactly like [awaitOpenResult]'s own fake.
class _ManualVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: filePath,
      filePath: filePath,
      duration: Duration.zero,
      opened: false,
    ));
  }

  void emitLoadingFor(String source) => emit(state.copyWith(
        status: PlaybackStatus.loading,
        fileName: source,
        filePath: source,
        duration: Duration.zero,
        opened: false,
      ));

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
  const src = 'https://youtu.be/abc';

  setUp(() => core = _ManualVideoCore());
  tearDown(() => core.dispose());

  test('a rejection is detected even though the backend load never completes',
      () async {
    // The real trap (#228): media_kit delivers the open error on a separate
    // stream while Player.open stays pending forever. If the coordinator
    // awaited the backend Future it would hang here and never see the error.
    final neverCompletes = Completer<void>();
    final result = coordinateOpen(
      core,
      source: src,
      startLoad: () {
        core.emitLoadingFor(src); // the synchronous _beginLoad emit
        return neverCompletes.future;
      },
    );
    core.emitError(); // the rejection arrives on the state stream
    expect(await result, isFalse);
    expect(neverCompletes.isCompleted, isFalse); // proof it never resolved
  });

  test('a confirmed open resolves to true without waiting on the backend',
      () async {
    final neverCompletes = Completer<void>();
    final result = coordinateOpen(
      core,
      source: src,
      startLoad: () {
        core.emitLoadingFor(src);
        return neverCompletes.future;
      },
    );
    core.emitOpened();
    expect(await result, isTrue);
  });

  test('a backend load that throws does not surface as an unhandled error',
      () async {
    // The abandoned attempt's Future must be error-observed; a throw here that
    // escaped would crash the zone in production.
    final result = coordinateOpen(
      core,
      source: src,
      startLoad: () async {
        core.emitLoadingFor(src);
        throw StateError('backend blew up after emitting loading');
      },
    );
    core.emitError();
    expect(await result, isFalse);
    // Give the thrown future a microtask turn to settle; the test passing
    // (no unhandled exception) is the assertion.
    await Future<void>.delayed(Duration.zero);
  });

  test('times out to false when neither open nor error ever arrives', () async {
    final result = await coordinateOpen(
      core,
      source: src,
      startLoad: () async => core.emitLoadingFor(src),
      timeout: const Duration(milliseconds: 50),
    );
    expect(result, isFalse);
  });
}
