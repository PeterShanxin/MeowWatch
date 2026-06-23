import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/whats_new_gate.dart';

void main() {
  group('shouldShowWhatsNew', () {
    test('no record (null) → false (fresh install)', () {
      expect(shouldShowWhatsNew(lastSeen: null, current: '0.33.0-alpha'), false);
    });

    test('empty/whitespace record → false', () {
      expect(shouldShowWhatsNew(lastSeen: '', current: '0.33.0-alpha'), false);
      expect(shouldShowWhatsNew(lastSeen: '   ', current: '0.33.0-alpha'), false);
    });

    test('no record but prior install → true (existing user predating the key)',
        () {
      // The release that introduces the modal must still show it to users who
      // updated into it — they have a DB but no recorded version yet.
      expect(
        shouldShowWhatsNew(
          lastSeen: null,
          current: '0.33.0-alpha',
          hasPriorInstall: true,
        ),
        true,
      );
      expect(
        shouldShowWhatsNew(
          lastSeen: '  ',
          current: '0.33.0-alpha',
          hasPriorInstall: true,
        ),
        true,
      );
    });

    test('hasPriorInstall is ignored once a real version is recorded', () {
      // A recorded same version still suppresses, regardless of the flag.
      expect(
        shouldShowWhatsNew(
          lastSeen: '0.33.0-alpha',
          current: '0.33.0-alpha',
          hasPriorInstall: true,
        ),
        false,
      );
    });

    test('same version → false', () {
      expect(
        shouldShowWhatsNew(lastSeen: '0.33.0-alpha', current: '0.33.0-alpha'),
        false,
      );
    });

    test('genuine upgrade (older recorded) → true', () {
      expect(
        shouldShowWhatsNew(lastSeen: '0.32.0-alpha', current: '0.33.0-alpha'),
        true,
      );
      // A multi-version jump is still a single upgrade.
      expect(
        shouldShowWhatsNew(lastSeen: '0.31.2-alpha', current: '0.34.0-alpha'),
        true,
      );
    });

    test('downgrade / older current → false (never shows on a version drop)',
        () {
      // The crux of the shared-data fix: an OLDER build run on the same machine
      // must not trigger the modal just because the recorded version is newer.
      expect(
        shouldShowWhatsNew(lastSeen: '0.34.0-alpha', current: '0.33.0-alpha'),
        false,
      );
      // hasPriorInstall must not override a recorded newer version either.
      expect(
        shouldShowWhatsNew(
          lastSeen: '0.34.0-alpha',
          current: '0.33.0-alpha',
          hasPriorInstall: true,
        ),
        false,
      );
    });

    test('alpha → stable of the same number counts as an upgrade', () {
      expect(
        shouldShowWhatsNew(lastSeen: '0.33.0-alpha', current: '0.33.0'),
        true,
      );
    });

    test('trims surrounding whitespace before comparing', () {
      expect(
        shouldShowWhatsNew(lastSeen: ' 0.33.0-alpha ', current: '0.33.0-alpha'),
        false,
      );
    });
  });

  group('lastSeenToPersist (high-water mark)', () {
    test('no record → record the current version', () {
      expect(lastSeenToPersist(stored: null, current: '0.34.0-alpha'),
          '0.34.0-alpha');
      expect(lastSeenToPersist(stored: '', current: '0.34.0-alpha'),
          '0.34.0-alpha');
      expect(lastSeenToPersist(stored: '   ', current: '0.34.0-alpha'),
          '0.34.0-alpha');
    });

    test('upgrade → advance to the current version', () {
      expect(lastSeenToPersist(stored: '0.33.0-alpha', current: '0.34.0-alpha'),
          '0.34.0-alpha');
    });

    test('same version → null (nothing to write)', () {
      expect(
        lastSeenToPersist(stored: '0.34.0-alpha', current: '0.34.0-alpha'),
        isNull,
      );
    });

    test('downgrade → null (never lower the recorded version)', () {
      // An older build on the same machine must never drag the high-water mark
      // back down — that is what made the modal ping-pong between two installs.
      expect(
        lastSeenToPersist(stored: '0.34.0-alpha', current: '0.33.0-alpha'),
        isNull,
      );
    });

    test('trims before comparing', () {
      expect(
        lastSeenToPersist(stored: ' 0.34.0-alpha ', current: '0.34.0-alpha'),
        isNull,
      );
    });
  });
}
