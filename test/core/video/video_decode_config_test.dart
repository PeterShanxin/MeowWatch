import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/video_decode_config.dart';

void main() {
  group('resolveHwdec', () {
    test('Windows hardware path resolves to d3d11va (zero-copy)', () {
      expect(resolveHwdec(forceSoftware: false, isWindows: true), 'd3d11va');
    });

    test('non-Windows hardware path resolves to auto-safe', () {
      expect(resolveHwdec(forceSoftware: false, isWindows: false), 'auto-safe');
    });

    test('forced-software path resolves to no, regardless of platform', () {
      expect(resolveHwdec(forceSoftware: true, isWindows: true), 'no');
      expect(resolveHwdec(forceSoftware: true, isWindows: false), 'no');
    });
  });

  group('resolveVideoSync', () {
    test('default resolves to display-resample', () {
      expect(resolveVideoSync(forceAudioSync: false), 'display-resample');
    });

    test('forced-audio-sync resolves to audio (mpv default)', () {
      expect(resolveVideoSync(forceAudioSync: true), 'audio');
    });
  });

  group('forceAudioSyncFromEnv', () {
    test('unset env var means display-resample (false)', () {
      expect(forceAudioSyncFromEnv(const {}), isFalse);
    });

    test('"1" forces audio sync', () {
      expect(
        forceAudioSyncFromEnv(const {forceAudioSyncEnvVar: '1'}),
        isTrue,
      );
    });

    test('"true" forces audio sync regardless of case', () {
      expect(
        forceAudioSyncFromEnv(const {forceAudioSyncEnvVar: 'TRUE'}),
        isTrue,
      );
    });

    test('"yes" and "on" force audio sync', () {
      expect(
        forceAudioSyncFromEnv(const {forceAudioSyncEnvVar: 'yes'}),
        isTrue,
      );
      expect(
        forceAudioSyncFromEnv(const {forceAudioSyncEnvVar: 'on'}),
        isTrue,
      );
    });

    test('surrounding whitespace is tolerated', () {
      expect(
        forceAudioSyncFromEnv(const {forceAudioSyncEnvVar: '  1  '}),
        isTrue,
      );
    });

    test('"0", "false", and empty mean display-resample (false)', () {
      expect(
        forceAudioSyncFromEnv(const {forceAudioSyncEnvVar: '0'}),
        isFalse,
      );
      expect(
        forceAudioSyncFromEnv(const {forceAudioSyncEnvVar: 'false'}),
        isFalse,
      );
      expect(
        forceAudioSyncFromEnv(const {forceAudioSyncEnvVar: ''}),
        isFalse,
      );
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
