import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/update_service.dart';

void main() {
  final script = buildUpdaterScript(
    extractedDir: r'C:\tmp\meow\extracted',
    appDir: r'D:\MeowWatch-windows-x64',
    tempDir: r'C:\tmp\meow',
    exeName: 'meowwatch.exe',
  );

  test('runs robocopy and not a Copy-Item command (only a comment mentions it)', () {
    expect(script, contains('robocopy '));
    expect(script, isNot(contains('Copy-Item -')));
  });

  test('writes Windows paths verbatim (single backslash, PS-literal)', () {
    expect(script, contains(r'robocopy "C:\tmp\meow\extracted" "D:\MeowWatch-windows-x64"'));
  });

  test('only restarts when the copy succeeded (exit code guard)', () {
    expect(script, contains(r'$LASTEXITCODE'));
    expect(script, contains('not restarting'));
    // The restart line passes the exe and a working directory.
    expect(script, contains(r'Start-Process -FilePath "D:\MeowWatch-windows-x64\meowwatch.exe"'));
    expect(script, contains(r'-WorkingDirectory "D:\MeowWatch-windows-x64"'));
  });

  test('writes a diagnostic log under the temp dir', () {
    expect(script, contains(r'C:\tmp\meow\updater.log'));
  });
}
