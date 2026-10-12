import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Execute the checked-in Bash steps with inert command substitutes. No GitHub
// calls, downloads, commits or pushes are made by these tests.
void main() {
  final workflow = File(
    '.github/workflows/ytdlp-pin.yml',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final bash = Platform.isWindows
      ? '${Platform.environment['ProgramFiles']}\\Git\\bin\\bash.exe'
      : 'bash';

  String stepScript(String name) {
    final start = workflow.indexOf('      - name: $name');
    expect(start, greaterThanOrEqualTo(0));
    final next = workflow.indexOf('\n      - ', start + 1);
    final step = workflow.substring(start, next < 0 ? workflow.length : next);
    final run = step.indexOf('        run: |\n');
    expect(run, greaterThanOrEqualTo(0));
    return step
        .substring(run + '        run: |\n'.length)
        .split('\n')
        .takeWhile((line) => line.isEmpty || line.startsWith('          '))
        .map((line) => line.isEmpty ? line : line.substring(10))
        .join('\n');
  }

  Future<ProcessResult> runStep(
    String name, {
    String response = 'true',
    String error = '',
    int status = 0,
  }) async {
    final temp = Directory.systemTemp.createTempSync('ytdlp-preflight-test-');
    try {
      final script = File('${temp.path}/step.sh');
      script.writeAsStringSync('''
gh() {
  printf '%s\\n' "\$TEST_RESPONSE"
  printf '%s\\n' "\$TEST_ERROR" >&2
  return "\$TEST_STATUS"
}
git() { printf 'git %s\\n' "\$*"; }
python3() { cat >/dev/null; }
export RUNNER_TEMP="\$PWD"
${stepScript(name)}
echo STEP_COMPLETED
''');
      return await Process.run(
        bash,
        ['--noprofile', '--norc', 'step.sh'],
        workingDirectory: temp.path,
        environment: {
          'TEST_RESPONSE': response,
          'TEST_ERROR': error,
          'TEST_STATUS': '$status',
          'GH_TOKEN': 'test-only',
          'GITHUB_TOKEN': 'test-only',
          'GITHUB_REPOSITORY': 'example/repo',
          'BRANCH': 'ci/ytdlp-test',
          'CURRENT': '2026.01.01',
          'VERSION': '2026.01.02',
          'PIN_FILE': 'pin.dart',
        },
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  }

  const preflight = 'Preflight — Actions may open PRs';

  test('403 cannot read setting and does not block the pin check', () async {
    final result = await runStep(
      preflight,
      response: '{"message":"Resource not accessible by integration"}',
      error: 'gh: Resource not accessible by integration (HTTP 403)',
      status: 1,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('::warning::'));
    expect(result.stdout, contains('Cannot read'));
    expect(result.stdout, isNot(contains('is OFF')));
    expect(result.stdout, contains('STEP_COMPLETED'));
  });

  test('explicitly disabled setting stops before later work', () async {
    final result = await runStep(preflight, response: 'false');
    expect(result.exitCode, isNot(0));
    expect(result.stdout, contains('is OFF'));
    expect(result.stdout, isNot(contains('STEP_COMPLETED')));
  });

  test('allowed setting continues', () async {
    final result = await runStep(preflight);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('STEP_COMPLETED'));
    expect(result.stdout, isNot(contains('::warning::')));
  });

  for (final error in [
    'gh: Bad credentials (HTTP 401)',
    'gh: Not Found (HTTP 404)',
    'gh: Internal Server Error (HTTP 500)',
    'error connecting to api.github.com',
  ]) {
    test('other lookup errors fail with their diagnostic: $error', () async {
      final result = await runStep(preflight, error: error, status: 1);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains(error));
      expect(result.stdout, contains('::error::'));
      expect(result.stdout, isNot(contains('is OFF')));
      expect(result.stdout, isNot(contains('STEP_COMPLETED')));
    });
  }

  for (final value in ['', 'null', 'unexpected']) {
    test('unexpected setting value is not called disabled: "$value"', () async {
      final result = await runStep(preflight, response: value);
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('::error::'));
      expect(result.stdout, isNot(contains('is OFF')));
      expect(result.stdout, isNot(contains('STEP_COMPLETED')));
    });
  }

  test(
    'PR creation failure keeps diagnostic and names the pushed branch',
    () async {
      final result = await runStep(
        'Push the branch and open the PR',
        error:
            'GraphQL: GitHub Actions is not permitted to create pull requests',
        status: 1,
      );
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('GitHub Actions is not permitted'));
      expect(result.stdout, contains('::error::'));
      expect(result.stdout, contains('ci/ytdlp-test'));
      expect(result.stdout, contains('Workflow permissions'));
      expect(result.stdout, isNot(contains('STEP_COMPLETED')));
    },
  );

  test(
    'successful PR creation completes without an error annotation',
    () async {
      final result = await runStep(
        'Push the branch and open the PR',
        response: 'https://github.com/example/repo/pull/1',
      );
      expect(result.exitCode, 0);
      expect(result.stdout, contains('https://github.com/example/repo/pull/1'));
      expect(result.stdout, contains('STEP_COMPLETED'));
      expect(result.stdout, isNot(contains('::error::')));
    },
  );
}
