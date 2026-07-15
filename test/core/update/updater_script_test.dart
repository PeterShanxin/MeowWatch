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

  test('restart:false swaps files but does not relaunch the app (#62)', () {
    final noRestart = buildUpdaterScript(
      extractedDir: r'C:\tmp\meow\extracted',
      appDir: r'D:\MeowWatch-windows-x64',
      tempDir: r'C:\tmp\meow',
      exeName: 'meowwatch.exe',
      restart: false,
    );
    // Still copies the new files over the install...
    expect(noRestart, contains('robocopy '));
    // ...but never relaunches the app the user just closed.
    expect(noRestart, isNot(contains('Start-Process -FilePath')));
    expect(noRestart, contains('not restarting (app closed)'));
  });

  test('writes a diagnostic log under the temp dir', () {
    expect(script, contains(r'C:\tmp\meow\updater.log'));
  });

  test('cleans up its own script, the VBS shim, and payload but keeps the log',
      () {
    expect(script, contains(r'Remove-Item -LiteralPath $PSCommandPath'));
    expect(script, contains(r'C:\tmp\meow\update.zip'));
    // The VBS launch shim is also removed (it finished the moment PowerShell
    // started, so deleting it here is safe).
    expect(script, contains(r'C:\tmp\meow\updater.vbs'));
    // The log file is never deleted.
    expect(script, isNot(contains(r'Remove-Item -Path "C:\tmp\meow\updater.log"')));
  });

  group('buildUpdaterVbs (PowerShell console created hidden — no flash, #197)',
      () {
    final vbs = buildUpdaterVbs(scriptPath: r'C:\tmp\meow\updater.ps1');

    test('runs powershell via WScript.Shell with window style 0, not waiting',
        () {
      // `.Run cmd, 0, False`: 0 = SW_HIDE at process creation (the console
      // never appears, unlike -WindowStyle Hidden which hides it after
      // PowerShell boots), False = don't block wscript on the updater.
      expect(vbs, contains('WScript.Shell'));
      expect(vbs, contains('powershell'));
      expect(vbs, contains(', 0, False'));
    });

    test('quotes the script path for VBScript (doubled quotes)', () {
      expect(vbs, contains(r'""C:\tmp\meow\updater.ps1""'));
    });

    test('keeps execution-policy bypass and hidden window style', () {
      expect(vbs, contains('-ExecutionPolicy Bypass'));
      expect(vbs, contains('-WindowStyle Hidden'));
    });
  });

  group('buildUpdaterLaunch (no console window, outlives the app)', () {
    final launch = buildUpdaterLaunch(vbsPath: r'C:\tmp\meow\updater.vbs');

    test('routes through cmd /c start, escaping the job object', () {
      // A directly-spawned detached child stays inside our Windows job object,
      // so exit(0) kills it before it runs — the silent auto-update bug.
      // `start` re-parents it outside our process tree.
      expect(launch.executable, 'cmd');
      expect(launch.arguments.take(2).toList(), ['/c', 'start']);
    });

    test('passes the empty title arg so a quoted path is not read as title',
        () {
      // `start ["title"] command` — the '' placeholder must precede wscript.
      final startIdx = launch.arguments.indexOf('start');
      expect(launch.arguments[startIdx + 1], '');
      expect(launch.arguments[startIdx + 2], 'wscript');
    });

    test('starts wscript (GUI subsystem → no console) on the VBS shim', () {
      // start on a console app (powershell) creates a visible console window
      // for the whole updater run (#197); wscript is a GUI-subsystem exe, so
      // no console is ever allocated.
      expect(launch.arguments, contains('wscript'));
      expect(launch.arguments, contains('//B'));
      expect(launch.arguments.last, r'C:\tmp\meow\updater.vbs');
      expect(launch.arguments, isNot(contains('powershell')));
    });
  });
}
