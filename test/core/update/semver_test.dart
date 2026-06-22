import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/semver.dart';

void main() {
  group('isVersionNewer', () {
    test('compares numeric MAJOR.MINOR.PATCH slots', () {
      expect(isVersionNewer('0.33.0', '0.32.0'), isTrue);
      expect(isVersionNewer('1.0.0', '0.99.99'), isTrue);
      expect(isVersionNewer('0.32.0', '0.33.0'), isFalse);
      expect(isVersionNewer('0.33.0', '0.33.0'), isFalse); // equal
    });

    test('a release with no pre-release tag outranks a tagged one', () {
      expect(isVersionNewer('1.0.0', '1.0.0-alpha'), isTrue);
      expect(isVersionNewer('1.0.0-alpha', '1.0.0'), isFalse);
      expect(isVersionNewer('1.0.0-beta', '1.0.0-alpha'), isTrue);
    });

    test('ignores a leading v and pads missing slots', () {
      expect(isVersionNewer('v0.33.0-alpha', 'v0.32.0-alpha'), isTrue);
      expect(isVersionNewer('0.33', '0.32.9'), isTrue); // 0.33 → 0.33.0
    });

    test('never throws on garbage segments (degrades to 0)', () {
      expect(() => isVersionNewer('x.y.z', '0.0.0'), returnsNormally);
      expect(isVersionNewer('x.y.z', '0.0.0'), isFalse);
    });
  });
}
