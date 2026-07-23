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

  test('ignores a lingering previous source until this load emits, then '
      'honors ours (fast room-switch-then-load)', () async {
    // The engine is reused across rooms: when a load starts right after leaving
    // a room, _beginLoad awaits the previous room's reset before emitting our
    // `loading`, so at first `core.state` is still the PREVIOUS video. That must
    // not read as a supersede and fail our load before it has begun.
    core.emitLoadingFor('https://youtu.be/PREVIOUS');
    final future = coordinateOpen(
      core,
      source: src,
      startLoad: () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        core.emitLoadingFor(src); // our loading finally emits
      },
    );
    var settled = false;
    unawaited(future.then((_) => settled = true));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(settled, isFalse,
        reason: 'must not supersede on the lingering previous-room state');

    await Future<void>.delayed(const Duration(milliseconds: 10));
    core.emitOpened(); // our source opens for real
    expect(await future, isTrue);
  });

  test('a different source taking over AFTER ours appeared is a real supersede',
      () async {
    final future = coordinateOpen(
      core,
      source: src,
      startLoad: () async => core.emitLoadingFor(src),
    );
    await Future<void>.delayed(Duration.zero); // let ours register
    core.emitLoadingFor('https://youtu.be/NEWER'); // a newer load overtakes
    expect(await future, isFalse);
  });
}
