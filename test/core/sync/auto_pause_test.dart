import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/auto_pause.dart';

void main() {
  group('decideAutoPause', () {
    test('fires on the healthy -> unhealthy edge while playing', () {
      expect(
        decideAutoPause(wasHealthy: true, nowHealthy: false, isPlaying: true),
        isTrue,
      );
    });

    test('does not fire when already paused', () {
      expect(
        decideAutoPause(wasHealthy: true, nowHealthy: false, isPlaying: false),
        isFalse,
      );
    });

    test('does not fire when sync stays healthy', () {
      expect(
        decideAutoPause(wasHealthy: true, nowHealthy: true, isPlaying: true),
        isFalse,
      );
    });

    test('does not fire when it was already unhealthy (no edge)', () {
      // e.g. user deliberately hits play again while alone — stay playing.
      expect(
        decideAutoPause(wasHealthy: false, nowHealthy: false, isPlaying: true),
        isFalse,
      );
    });

    test('does not fire when sync is recovering (unhealthy -> healthy)', () {
      expect(
        decideAutoPause(wasHealthy: false, nowHealthy: true, isPlaying: true),
        isFalse,
      );
    });
  });

  group('SyncHealth.healthy', () {
    test('healthy only when connected AND a peer is present', () {
      expect(const SyncHealth(connected: true, hasPeer: true).healthy, isTrue);
      expect(
          const SyncHealth(connected: true, hasPeer: false).healthy, isFalse);
      expect(
          const SyncHealth(connected: false, hasPeer: true).healthy, isFalse);
      expect(
          const SyncHealth(connected: false, hasPeer: false).healthy, isFalse);
    });
  });
}
