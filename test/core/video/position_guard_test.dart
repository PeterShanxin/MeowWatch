import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/position_guard.dart';

void main() {
  group('acceptPlayerPosition', () {
    test('accepts 0:00 even when the duration is unknown (fresh load)', () {
      expect(
        acceptPlayerPosition(
          incoming: Duration.zero,
          duration: Duration.zero,
        ),
        isTrue,
      );
    });

    test('rejects a non-zero position while the duration is still unknown', () {
      // The #132 case: after load() resets duration to 0, libmpv can still
      // deliver the previous file's end-of-file position. Drop it so the new
      // episode opens at 0:00.
      expect(
        acceptPlayerPosition(
          incoming: const Duration(minutes: 24),
          duration: Duration.zero,
        ),
        isFalse,
      );
    });

    test('accepts a normal mid-file position within the duration', () {
      expect(
        acceptPlayerPosition(
          incoming: const Duration(seconds: 60),
          duration: const Duration(minutes: 2),
        ),
        isTrue,
      );
    });

    test('accepts the exact end-of-file position', () {
      expect(
        acceptPlayerPosition(
          incoming: const Duration(minutes: 2),
          duration: const Duration(minutes: 2),
        ),
        isTrue,
      );
    });

    test('accepts a tiny overrun past the duration (rounding)', () {
      expect(
        acceptPlayerPosition(
          incoming: const Duration(minutes: 2, milliseconds: 1),
          duration: const Duration(minutes: 2),
        ),
        isTrue,
      );
    });

    test('rejects a stale position well beyond the new file duration', () {
      // Previous episode (24 min) end leaking in while a shorter new file
      // (3 min) is loaded — clearly out of range, so it's dropped.
      expect(
        acceptPlayerPosition(
          incoming: const Duration(minutes: 24),
          duration: const Duration(minutes: 3),
        ),
        isFalse,
      );
    });
  });
}
