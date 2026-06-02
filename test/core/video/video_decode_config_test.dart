import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/video_decode_config.dart';

void main() {
  group('resolveHwdec', () {
    test('hardware path resolves to auto-safe (engages Adreno etc.)', () {
      expect(resolveHwdec(forceSoftware: false), 'auto-safe');
    });

    test('forced-software path resolves to no', () {
      expect(resolveHwdec(forceSoftware: true), 'no');
    });
  });

  group('forceSoftwareDecodeFromEnv', () {
    test('unset env var means hardware decode (false)', () {
      expect(forceSoftwareDecodeFromEnv(const {}), isFalse);
    });

    test('"1" forces software', () {
      expect(
        forceSoftwareDecodeFromEnv(const {forceSoftwareDecodeEnvVar: '1'}),
        isTrue,
      );
    });

    test('"true" forces software regardless of case', () {
      expect(
        forceSoftwareDecodeFromEnv(const {forceSoftwareDecodeEnvVar: 'TRUE'}),
        isTrue,
      );
    });

    test('"yes" and "on" force software', () {
      expect(
        forceSoftwareDecodeFromEnv(const {forceSoftwareDecodeEnvVar: 'yes'}),
        isTrue,
      );
      expect(
        forceSoftwareDecodeFromEnv(const {forceSoftwareDecodeEnvVar: 'on'}),
        isTrue,
      );
    });

    test('surrounding whitespace is tolerated', () {
      expect(
        forceSoftwareDecodeFromEnv(const {forceSoftwareDecodeEnvVar: '  1  '}),
        isTrue,
      );
    });

    test('"0", "false", and empty mean hardware decode (false)', () {
      expect(
        forceSoftwareDecodeFromEnv(const {forceSoftwareDecodeEnvVar: '0'}),
        isFalse,
      );
      expect(
        forceSoftwareDecodeFromEnv(const {forceSoftwareDecodeEnvVar: 'false'}),
        isFalse,
      );
      expect(
        forceSoftwareDecodeFromEnv(const {forceSoftwareDecodeEnvVar: ''}),
        isFalse,
      );
    });
  });
}
