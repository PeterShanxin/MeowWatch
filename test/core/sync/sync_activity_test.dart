import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_activity.dart';

void main() {
  SyncActivity? classify({
    required bool peerPaused,
    required bool localPaused,
    bool doSeek = false,
    Duration peerPos = const Duration(seconds: 100),
    Duration localPos = const Duration(seconds: 100),
    String? setBy = 'lin',
  }) =>
      classifySyncActivity(
        global: PeerPlayState(
          position: peerPos,
          paused: peerPaused,
          doSeek: doSeek,
          setBy: setBy,
        ),
        localPaused: localPaused,
        localPosition: localPos,
      );

  test('pause flip → paused at peer position', () {
    final a = classify(peerPaused: true, localPaused: false);
    expect(a, isNotNull);
    expect(a!.kind, SyncActivityKind.paused);
    expect(a.username, 'lin');
    expect(a.position, const Duration(seconds: 100));
  });

  test('play flip → played', () {
    final a = classify(peerPaused: false, localPaused: true);
    expect(a!.kind, SyncActivityKind.played);
  });

  test('forward seek → seekedForward', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(seconds: 500),
      localPos: const Duration(seconds: 100),
    );
    expect(a!.kind, SyncActivityKind.seekedForward);
    expect(a.position, const Duration(seconds: 500));
  });

  test('backward seek → seekedBack', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(seconds: 30),
      localPos: const Duration(seconds: 100),
    );
    expect(a!.kind, SyncActivityKind.seekedBack);
  });

  test('micro-seek within noise threshold → null', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(milliseconds: 100600),
      localPos: const Duration(seconds: 100),
    );
    expect(a, isNull);
  });

  test('drift rewind (no flip, no seek) → null', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      peerPos: const Duration(seconds: 80),
      localPos: const Duration(seconds: 100),
    );
    expect(a, isNull);
  });

  test('unattributable (setBy null) → null', () {
    final a = classify(peerPaused: true, localPaused: false, setBy: null);
    expect(a, isNull);
  });
}
