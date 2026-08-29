import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/startup_env.dart';

void main() {
  List<String> lines() => startupEnvLines(
    version: '0.31.0-alpha',
    os: 'Windows 11 (10.0.26200)',
    logPath: r'%USERPROFILE%\AppData\meowwatch_sync-2026.log',
    window: '1280x720',
    dpr: 1.5,
    locale: 'en_US',
    theme: 'midnight',
    cardSize: '320x240',
    logLevel: 'verbose',
  );

  test('first line is the versioned app-start marker', () {
    expect(lines().first, 'life: app start (version=0.31.0-alpha)');
  });

  test('includes os, window/dpr/locale, log path, and settings', () {
    final all = lines().join('\n');
    expect(all, contains('env: os=Windows 11 (10.0.26200)'));
    expect(all, contains('env: window=1280x720 dpr=1.50 locale=en_US'));
    expect(all, contains(r'env: logfile=%USERPROFILE%\AppData\meowwatch_sync-2026.log'));
    expect(all, contains('env: settings theme=midnight cardSize=320x240 logLevel=verbose'));
  });

  test('every line is neat-kept (no trace:/raw/apply=false markers)', () {
    for (final l in lines()) {
      expect(l.startsWith('trace:'), isFalse, reason: l);
      expect(l.startsWith('<<') || l.startsWith('>>'), isFalse, reason: l);
    }
  });
}
