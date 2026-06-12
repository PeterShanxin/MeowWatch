import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/log_level.dart';

void main() {
  group('logLevelFromName', () {
    test('maps known names to levels', () {
      expect(logLevelFromName('off'), LogLevel.off);
      expect(logLevelFromName('neat'), LogLevel.neat);
      expect(logLevelFromName('verbose'), LogLevel.verbose);
    });

    test('defaults to verbose for null / empty / unknown', () {
      expect(logLevelFromName(null), LogLevel.verbose);
      expect(logLevelFromName(''), LogLevel.verbose);
      expect(logLevelFromName('whatever'), LogLevel.verbose);
    });

    test('is case-insensitive and trims', () {
      expect(logLevelFromName('OFF'), LogLevel.off);
      expect(logLevelFromName('  Neat  '), LogLevel.neat);
      expect(logLevelFromName('Verbose'), LogLevel.verbose);
    });

    test('round-trips through storageName', () {
      for (final level in LogLevel.values) {
        expect(logLevelFromName(level.storageName), level);
      }
    });
  });

  group('storageName', () {
    test('is the stable lowercase token', () {
      expect(LogLevel.off.storageName, 'off');
      expect(LogLevel.neat.storageName, 'neat');
      expect(LogLevel.verbose.storageName, 'verbose');
    });
  });
}
