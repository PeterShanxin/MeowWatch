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

  test('cleans up its own script and payload but keeps the log', () {
    expect(script, contains(r'Remove-Item -LiteralPath $PSCommandPath'));
    expect(script, contains(r'C:\tmp\meow\update.zip'));
    // The log file is never deleted.
    expect(script, isNot(contains(r'Remove-Item -Path "C:\tmp\meow\updater.log"')));
  });

  group('buildUpdaterLaunch (must outlive the app — escapes the job object)', () {
    final launch = buildUpdaterLaunch(scriptPath: r'C:\tmp\meow\updater.ps1');

    test('routes through cmd /c start, not a direct powershell spawn', () {
      // Spawning powershell directly leaves it inside our Windows job object,
      // so exit(0) kills it before it runs — the silent auto-update bug.
      // `start` re-parents it outside our process tree.
      expect(launch.executable, 'cmd');
      expect(launch.arguments.take(2).toList(), ['/c', 'start']);
    });

    test('passes the empty title arg so a quoted path is not read as title', () {
      // `start ["title"] command` — the '' placeholder must precede powershell.
      final startIdx = launch.arguments.indexOf('start');
      expect(launch.arguments[startIdx + 1], '');
      expect(launch.arguments[startIdx + 2], 'powershell');
    });

    test('runs the generated script hidden, with execution policy bypassed', () {
      expect(launch.arguments, containsAll(<String>['-ExecutionPolicy', 'Bypass']));
      expect(launch.arguments, containsAll(<String>['-WindowStyle', 'Hidden']));
      expect(launch.arguments, containsAllInOrder(<String>['-File', r'C:\tmp\meow\updater.ps1']));
    });
  });
}
