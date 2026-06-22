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
