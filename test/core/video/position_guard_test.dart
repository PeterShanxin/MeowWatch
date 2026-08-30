import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/position_guard.dart';

void main() {
  group('acceptPlayerPosition', () {
    test('accepts 0:00 in any state (fresh load sits here)', () {
      expect(
        acceptPlayerPosition(
          incoming: Duration.zero,
          duration: Duration.zero,
          started: false,
        ),
        isTrue,
      );
    });

    test('rejects one late probe-zero after an explicit non-zero seek', () {
      expect(
        acceptPlayerPosition(
          incoming: Duration.zero,
          current: const Duration(minutes: 18),
          duration: const Duration(minutes: 54),
          started: true,
          probeZeroPending: true,
        ),
        isFalse,
      );
    });

    test('accepts an explicit/fresh zero when no probe zero is pending', () {
      expect(
        acceptPlayerPosition(
          incoming: Duration.zero,
          current: const Duration(minutes: 18),
          duration: const Duration(minutes: 54),
          started: true,
        ),
        isTrue,
      );
    });

    test('rejects a non-zero position before playback has started', () {
      // The #132 case: after load() (play:false), libmpv can still deliver the
      // previous file's end-of-file position. Until the user plays/seeks the
      // new file sits at 0:00, so drop it.
      expect(
        acceptPlayerPosition(
          incoming: const Duration(minutes: 24),
          duration: Duration.zero,
          started: false,
        ),
        isFalse,
      );
    });

    test('rejects a stale end that fits within a LONGER new file before start '
        '(Codex review)', () {
      // A ends at 23:55; the longer B reports 24:10 before the stale 23:55
      // tick arrives. A pure range check would wrongly accept 23:55 — but
      // playback has not started, so it is rejected.
      expect(
        acceptPlayerPosition(
          incoming: const Duration(minutes: 23, seconds: 55),
          duration: const Duration(minutes: 24, seconds: 10),
          started: false,
        ),
        isFalse,
      );
    });

    test('accepts a normal mid-file position once started', () {
      expect(
        acceptPlayerPosition(
          incoming: const Duration(seconds: 60),
          duration: const Duration(minutes: 2),
          started: true,
        ),
        isTrue,
      );
    });

    test('accepts the exact end-of-file position once started', () {
      expect(
        acceptPlayerPosition(
          incoming: const Duration(minutes: 2),
          duration: const Duration(minutes: 2),
          started: true,
        ),
        isTrue,
      );
    });

    test(
      'accepts a tiny overrun past the duration (rounding) once started',
      () {
        expect(
          acceptPlayerPosition(
            incoming: const Duration(minutes: 2, milliseconds: 1),
            duration: const Duration(minutes: 2),
            started: true,
          ),
          isTrue,
        );
      },
    );

    test('rejects a position beyond the duration even once started', () {
      expect(
        acceptPlayerPosition(
          incoming: const Duration(minutes: 24),
          duration: const Duration(minutes: 3),
          started: true,
        ),
        isFalse,
      );
    });

    test('rejects a non-zero position with unknown duration once started', () {
      expect(
        acceptPlayerPosition(
          incoming: const Duration(seconds: 5),
          duration: Duration.zero,
          started: true,
        ),
        isFalse,
      );
    });
  });
}
