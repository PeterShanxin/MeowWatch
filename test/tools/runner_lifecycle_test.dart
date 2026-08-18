import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tool/runner.ps1 unit tests', () {
    test(
      'passes all runner lifecycle and scoping unit tests in PowerShell',
      () async {
        if (!Platform.isWindows) return;

        final scriptPath = 'test/tools/runner_lifecycle_test.ps1';
        expect(File(scriptPath).existsSync(), isTrue);

        // Try pwsh first, fallback to powershell
        var result = await Process.run('pwsh', ['-File', scriptPath]);
        if (result.exitCode != 0 &&
            result.stderr.toString().contains('is not recognized')) {
          result = await Process.run('powershell', [
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptPath,
          ]);
        }

        expect(
          result.exitCode,
          0,
          reason:
              'PowerShell test output:\n${result.stdout}\nErrors:\n${result.stderr}',
        );
        expect(result.stdout.toString(), contains('0 failed'));
      },
    );
  });
}
