import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/duration_open_gate.dart';

void main() {
  group('evaluateDurationEvent', () {
    test('a duration:0 reset arms the latch but is never open evidence', () {
      // media_kit emits duration:0 inside Player.open's stop(open:true), before
      // the demuxer reads the new container. It marks this load's boundary; it
      // is not itself a real duration.
      final r = evaluateDurationEvent(resetSeen: false, incoming: Duration.zero);
      expect(r.resetSeen, isTrue);
      expect(r.accept, isFalse);
    });

    test('a genuine duration after this load\'s reset is accepted', () {
      // The reset has been seen (latch armed); the demuxer now reports the real
      // container duration. This is the paused-load open evidence the old
      // cross-stream params gate wrongly dropped.
      final r = evaluateDurationEvent(
        resetSeen: true,
        incoming: const Duration(minutes: 69),
      );
      expect(r.accept, isTrue);
      expect(r.resetSeen, isTrue);
    });

    test('a late stale duration BEFORE this load\'s reset is dropped', () {
      // Reused engine (#137/#143): a duration from the source we just unloaded
      // can arrive while the next load is in flight. On the duration stream it
      // arrives before this load's duration:0 reset (FIFO), so the latch is
      // still false — drop it, or it would falsely mark the new source open.
      final r = evaluateDurationEvent(
        resetSeen: false,
        incoming: const Duration(minutes: 67),
      );
      expect(r.accept, isFalse);
      expect(r.resetSeen, isFalse);
    });

    test(
      'full episode-switch sequence: stale dropped, reset arms, real accepted',
      () {
        // Models the warm reused-engine ordering that produced the false 12s
        // timeout. Thread the latch through the stream exactly as the listener
        // does, starting each load with resetSeen=false.
        var resetSeen = false;

        // 1. A late end-duration from the previous episode overtakes the reset.
        var r = evaluateDurationEvent(
          resetSeen: resetSeen,
          incoming: const Duration(minutes: 67, seconds: 31),
        );
        resetSeen = r.resetSeen;
        expect(r.accept, isFalse, reason: 'stale previous-source duration');

        // 2. This load's START_FILE reset crosses the stream.
        r = evaluateDurationEvent(resetSeen: resetSeen, incoming: Duration.zero);
        resetSeen = r.resetSeen;
        expect(r.accept, isFalse);
        expect(resetSeen, isTrue);

        // 3. The new episode's real container duration — must be accepted so a
        //    paused load has open evidence and never hits the timeout.
        r = evaluateDurationEvent(
          resetSeen: resetSeen,
          incoming: const Duration(minutes: 69, seconds: 28),
        );
        expect(r.accept, isTrue);
      },
    );

    test('steady-state durations stay accepted once the latch is armed', () {
      final r = evaluateDurationEvent(
        resetSeen: true,
        incoming: const Duration(seconds: 1),
      );
      expect(r.accept, isTrue);
    });
  });
}
