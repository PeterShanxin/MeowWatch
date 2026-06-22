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

    test('different (older) recorded version → true', () {
      expect(
        shouldShowWhatsNew(lastSeen: '0.32.0-alpha', current: '0.33.0-alpha'),
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
}
