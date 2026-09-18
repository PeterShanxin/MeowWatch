import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _workflowPath = '.github/workflows/dependabot-review-routing.yml';

/// The `run: |` block of the routing step, de-indented to plain bash.
String _routingScript(String workflow) {
  final lines = workflow.split(RegExp(r'\r?\n'));
  final start = lines.indexWhere((line) => line.trim() == 'run: |');
  expect(start, isNot(-1), reason: 'routing step has no run block');
  final indent = ' ' * (lines[start].indexOf('run:') + 2);
  final body = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty) {
      body.add('');
      continue;
    }
    if (!line.startsWith(indent)) break;
    body.add(line.substring(indent.length));
  }
  return body.join('\n');
}

/// Git Bash on Windows; a bare `bash` there can resolve to WSL's System32 stub.
String _bash() {
  if (!Platform.isWindows) return 'bash';
  final programFiles =
      Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
  return '$programFiles\\Git\\bin\\bash.exe';
}

/// Runs the routing script with `curl` stubbed, returning the HTTP methods it
/// sent to the requested_reviewers endpoint (POST = request, DELETE = remove).
Future<List<String>> _route(
  String script, {
  required String author,
  required String event,
  String action = 'opened',
  String title = 'feat: something',
  String head = 'feat/something',
  String reviewAuthor = '',
  String reviewBody = '',
}) async {
  const stub = r'''
curl() {
  local method='' url='' data=''
  while (($#)); do
    case "$1" in
      -X) method="$2"; shift ;;
      -d) data="$2"; shift ;;
      https://*) url="$1" ;;
    esac
    shift
  done
  printf 'CURL\t%s\t%s\t%s\n' "$method" "$url" "$data" >&2
}
''';
  final process = await Process.start(
    _bash(),
    ['-s'],
    environment: {
      'GH_TOKEN': 'test-token',
      'REPOSITORY': 'PeterShanxin/MeowWatch',
      'PR_NUMBER': '1',
      'PR_AUTHOR': author,
      'PR_TITLE': title,
      'PR_HEAD': head,
      'EVENT_NAME': event,
      'EVENT_ACTION': action,
      'REVIEW_AUTHOR': reviewAuthor,
      'REVIEW_BODY': reviewBody,
    },
  );
  process.stdin.write('$stub\n$script\n');
  await process.stdin.close();
  final stderr = await process.stderr.transform(utf8.decoder).join();
  await process.stdout.drain<void>();
  final code = await process.exitCode;
  expect(code, 0, reason: 'routing script failed:\n$stderr');
  final calls = [
    for (final line in const LineSplitter().convert(stderr))
      if (line.startsWith('CURL\t')) line.split('\t'),
  ];
  for (final call in calls) {
    expect(call[2], endsWith('/pulls/1/requested_reviewers'));
    expect(jsonDecode(call[3]), {
      'reviewers': ['PeterShanxin'],
    });
  }
  return [for (final call in calls) call[1]];
}

void main() {
  late String workflow;
  late String script;

  setUpAll(() {
    workflow = File(_workflowPath).readAsStringSync();
    script = _routingScript(workflow);
  });

  test('never checks out or runs pull request code', () {
    expect(workflow, isNot(contains('actions/checkout')));
    expect(workflow, isNot(contains('github.event.pull_request.head.sha')));
    expect(workflow, isNot(contains('secrets.')));
    expect(workflow, contains('contents: read'));
  });

  test('only requests or removes reviewers, never approves', () {
    expect(workflow, isNot(contains('/reviews')));
    expect(workflow.toUpperCase(), isNot(contains('APPROVE')));
  });

  group('human pull requests', () {
    test('owner-authored PR does not request its author as reviewer', () async {
      for (final action in ['opened', 'reopened', 'ready_for_review']) {
        expect(
          await _route(
            script,
            author: 'PeterShanxin',
            event: 'pull_request_target',
            action: action,
          ),
          isEmpty,
          reason: action,
        );
      }
    });

    test('external contributor PR requests the maintainer', () async {
      for (final action in ['opened', 'reopened', 'ready_for_review']) {
        expect(
          await _route(
            script,
            author: 'someone-else',
            event: 'pull_request_target',
            action: action,
          ),
          ['POST'],
          reason: action,
        );
      }
    });

    test('pushes to an open PR do not re-request review', () async {
      expect(
        await _route(
          script,
          author: 'someone-else',
          event: 'pull_request_target',
          action: 'synchronize',
        ),
        isEmpty,
      );
    });

    test('review events on human PRs do not change routing', () async {
      for (final author in ['PeterShanxin', 'someone-else']) {
        expect(
          await _route(
            script,
            author: author,
            event: 'pull_request_review',
            action: 'submitted',
            reviewAuthor: 'cursor',
            reviewBody: 'Security agent passed',
          ),
          isEmpty,
          reason: author,
        );
      }
    });
  });

  group('Dependabot pull requests', () {
    const bot = 'dependabot[bot]';
    const compatibleTitle =
        'chore(deps): bump the compatible-dependencies group with 3 updates';
    const compatibleHead = 'dependabot/pub/compatible-dependencies-abc123';
    const majorTitle = 'chore(deps): bump drift from 2.28.0 to 3.0.0';
    const majorHead = 'dependabot/pub/drift-3.0.0';

    test('compatible group drops the review request', () async {
      expect(
        await _route(
          script,
          author: bot,
          event: 'pull_request_target',
          title: compatibleTitle,
          head: compatibleHead,
        ),
        ['DELETE'],
      );
    });

    test('major update requests the maintainer', () async {
      expect(
        await _route(
          script,
          author: bot,
          event: 'pull_request_target',
          title: majorTitle,
          head: majorHead,
        ),
        ['POST'],
      );
    });

    test('clean Cursor review keeps a compatible group quiet', () async {
      expect(
        await _route(
          script,
          author: bot,
          event: 'pull_request_review',
          action: 'submitted',
          title: compatibleTitle,
          head: compatibleHead,
          reviewAuthor: 'cursor',
          reviewBody: 'Bugbot reviewed. Security agent passed.',
        ),
        ['DELETE'],
      );
    });

    test(
      'Cursor finding on a compatible group requests the maintainer',
      () async {
        expect(
          await _route(
            script,
            author: bot,
            event: 'pull_request_review',
            action: 'submitted',
            title: compatibleTitle,
            head: compatibleHead,
            reviewAuthor: 'cursor',
            reviewBody: 'Security agent found 1 issue. Finding: token leak.',
          ),
          ['POST'],
        );
      },
    );

    test('Cursor review on a major update requests the maintainer', () async {
      expect(
        await _route(
          script,
          author: bot,
          event: 'pull_request_review',
          action: 'submitted',
          title: majorTitle,
          head: majorHead,
          reviewAuthor: 'cursor',
          reviewBody: 'Security agent passed.',
        ),
        ['POST'],
      );
    });

    test('non-Cursor review (e.g. Codex timeout) changes nothing', () async {
      expect(
        await _route(
          script,
          author: bot,
          event: 'pull_request_review',
          action: 'submitted',
          title: compatibleTitle,
          head: compatibleHead,
          reviewAuthor: 'chatgpt-codex-connector[bot]',
          reviewBody: 'Codex review timed out.',
        ),
        isEmpty,
      );
    });
  });
}
