import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

// A plain-Dart CLI under tool/, not shipped in the app. Import it directly, the
// same way release_signer_test.dart does.
import '../../tool/action_cache.dart';

void main() {
  group('splitWorkflowJobs', () {
    test('attributes each key to the job that owns it', () {
      final jobs = splitWorkflowJobs([
        'name: Build',
        'jobs:',
        '  check:',
        '    runs-on: [self-hosted, windows]',
        '  gate:',
        '    runs-on: ubuntu-latest',
      ].join('\n'));

      expect(jobs.keys, ['check', 'gate']);
      expect(jobs['check']!.join('\n'), contains('self-hosted'));
      expect(jobs['check']!.join('\n'), isNot(contains('ubuntu-latest')));
    });

    test('does not mistake a deeper valueless key for a job', () {
      final jobs = splitWorkflowJobs([
        'jobs:',
        '  build:',
        '    steps:',
        '      - uses: actions/checkout@v7',
        '    runs-on: [self-hosted, windows]',
      ].join('\n'));

      expect(jobs.keys, ['build']);
    });

    test('stops at the end of the jobs block', () {
      final jobs = splitWorkflowJobs([
        'jobs:',
        '  build:',
        '    runs-on: a',
        'permissions:',
        '  contents: write',
      ].join('\n'));

      expect(jobs.keys, ['build']);
      expect(jobs['build']!.join('\n'), isNot(contains('contents: write')));
    });

    test('returns nothing for a file with no jobs block', () {
      expect(splitWorkflowJobs('name: nothing\n'), isEmpty);
    });
  });

  group('foldRunsOn', () {
    test('reads the inline list form', () {
      expect(
        foldRunsOn(['    runs-on: [self-hosted, windows, meowwatch-ci]']),
        '[self-hosted, windows, meowwatch-ci]',
      );
    });

    test('folds a block scalar onto one line', () {
      expect(
        foldRunsOn([
          '    runs-on: >-',
          "      \${{ inputs.arch == 'arm64'",
          "      && fromJSON('[\"self-hosted\"]') }}",
        ]),
        contains('self-hosted'),
      );
    });

    test('is null when the job names no runner', () {
      expect(foldRunsOn(['    steps:']), isNull);
    });
  });

  group('parseActionUses', () {
    test('splits owner, repository and ref', () {
      final reference = parseActionUses('actions/checkout@v7')!;
      expect(reference.nameWithOwner, 'actions/checkout');
      expect(reference.ref, 'v7');
      expect(reference.subPath, '');
    });

    test('keeps the sub-path out of the repository name', () {
      // The archive is the whole repository; the sub-path selects an action
      // inside it and must never reach a cache path.
      final reference = parseActionUses('owner/repo/tools/lint@main')!;
      expect(reference.nameWithOwner, 'owner/repo');
      expect(reference.subPath, 'tools/lint');
    });

    test('returns null for references the cache cannot hold', () {
      expect(parseActionUses('./.github/workflows/build.yml'), isNull);
      expect(parseActionUses('docker://alpine:3'), isNull);
      expect(parseActionUses('actions/checkout'), isNull);
      expect(parseActionUses('actions/checkout@'), isNull);
      expect(parseActionUses('owner//repo@v1'), isNull);
      expect(parseActionUses(''), isNull);
    });
  });

  group('collectCacheableActions', () {
    const workflow = '''
jobs:
  check-self-hosted:
    runs-on: [self-hosted, windows, meowwatch-ci]
    steps:
      - uses: actions/checkout@v7
  check-hosted:
    runs-on: windows-2022
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
  build-windows-x64:
    runs-on: [self-hosted, windows, meowwatch-ci]
    steps:
      - uses: actions/checkout@v7
      # - uses: actions/retired@v1
''';

    test('collects only what a job on our own host would download', () {
      // A hosted runner cannot read this cache, so caching subosito/flutter-action
      // would be a download with no possible hit.
      expect(
        collectCacheableActions([workflow]).map((r) => r.uses),
        ['actions/checkout@v7'],
      );
    });

    test('ignores a commented-out step', () {
      expect(
        collectCacheableActions([workflow]).map((r) => r.uses),
        isNot(contains('actions/retired@v1')),
      );
    });
  });

  group("this repository's own workflows", () {
    test('derive the archives the self-hosted runner needs', () {
      // Pinned so that adding a self-hosted step which uses a new action is a
      // visible change here, rather than a silent extra download on every job.
      final workflows = Directory('.github/workflows')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.yml'))
          .map((file) => file.readAsStringSync());

      expect(
        collectCacheableActions(workflows).map((r) => r.uses),
        ['actions/checkout@v7'],
      );
    });

    test('PR and analyze jobs do not interpolate release secrets', () {
      final jobs = splitWorkflowJobs(
        File('.github/workflows/build.yml').readAsStringSync(),
      );
      for (final name in ['check-hosted', 'gate', 'check-self-hosted']) {
        final body = jobs[name]!.join('\n');
        expect(body, isNot(contains('secrets.MEOWWATCH_RELEASE_KEY')));
        expect(body, isNot(contains('secrets.R2_')));
        expect(body, isNot(contains('secrets.TAURI_SIGNING_PRIVATE_KEY')));
      }
      final tagBuild = jobs['build-windows-x64']!.join('\n');
      expect(tagBuild, contains('runs-on: windows-2022'));
      expect(tagBuild, contains('environment: release'));
      expect(tagBuild, contains('secrets.MEOWWATCH_RELEASE_KEY'));
      expect(tagBuild, isNot(contains('secrets.R2_')));
      final r2 = jobs['release']!.join('\n');
      expect(r2, contains('secrets.R2_'));
      expect(r2, isNot(contains('secrets.MEOWWATCH_RELEASE_KEY')));
    });
  });

  group('ActionCacheEntry', () {
    const sha = '3d3c42e5aac5ba805825da76410c181273ba90b1';

    test('matches the layout ActionManager builds on Windows', () {
      const entry = ActionCacheEntry(
        uses: 'actions/checkout@v7',
        resolvedNameWithOwner: 'actions/checkout',
        sha: sha,
      );
      expect(entry.relativePath, 'actions_checkout\\$sha.zip');
      expect(entry.url, 'https://codeload.github.com/actions/checkout/zip/$sha');
    });

    test('files a renamed repository under the name the API resolved', () {
      // The runner writes the archive under ResolvedNameWithOwner, so caching
      // it under the workflow's spelling would be a permanent miss.
      const entry = ActionCacheEntry(
        uses: 'old-owner/checkout@v7',
        resolvedNameWithOwner: 'actions/checkout',
        sha: sha,
      );
      expect(entry.relativePath, 'actions_checkout\\$sha.zip');
    });
  });

  group('composeEnvironmentFile', () {
    test('writes the setting into an empty file', () {
      expect(composeEnvironmentFile([], r'C:\cache'), [
        r'ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=C:\cache',
      ]);
    });

    test('leaves settings this repository does not own alone', () {
      // The runner's .env is shared; a future setting must survive a refresh.
      expect(composeEnvironmentFile(['SOMETHING_ELSE=1'], r'C:\cache'), [
        'SOMETHING_ELSE=1',
        r'ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=C:\cache',
      ]);
    });

    test('replaces every previous assignment rather than appending', () {
      // Two assignments would make the effective value depend on order.
      expect(
        composeEnvironmentFile([
          r'ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=C:\old',
          r'  ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE = C:\older',
          'KEEP=yes',
        ], r'C:\new'),
        ['KEEP=yes', r'ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=C:\new'],
      );
    });

    test('does not touch a different key that contains our name', () {
      expect(
        composeEnvironmentFile(
          ['NOTE_ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=elsewhere'],
          r'C:\cache',
        ).first,
        'NOTE_ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=elsewhere',
      );
    });

    test('is idempotent, because it runs before every runner start', () {
      final once = composeEnvironmentFile(['KEEP=yes'], r'C:\cache');
      expect(composeEnvironmentFile(once, r'C:\cache'), once);
    });

    test('does not accumulate a blank line per refresh', () {
      expect(composeEnvironmentFile(['KEEP=yes', '', ''], r'C:\cache').length, 2);
    });
  });

  group('isReadableZip', () {
    final archive = Archive()
      ..addFile(ArchiveFile('action.txt', 6, [104, 101, 108, 108, 111, 33]));
    final bytes = ZipEncoder().encode(archive);

    test('accepts a real archive', () {
      expect(isReadableZip(bytes), isTrue);
    });

    test('refuses a plausible non-zip body', () {
      // This is the shape that makes a length check useless: a rate-limit page
      // is a perfectly good file.
      expect(
        isReadableZip('You have exceeded a secondary rate limit.'.codeUnits),
        isFalse,
      );
    });

    test('refuses a truncated archive', () {
      expect(isReadableZip(bytes.sublist(0, bytes.length ~/ 2)), isFalse);
    });

    test('refuses nothing at all', () {
      expect(isReadableZip(const []), isFalse);
    });
  });

  group('staleArchives', () {
    test('names only the archives no workflow asks for', () {
      expect(
        staleArchives(
          present: ['actions_checkout\\aaa.zip', 'actions_checkout\\bbb.zip'],
          planned: ['actions_checkout\\bbb.zip'],
        ),
        ['actions_checkout\\aaa.zip'],
      );
    });

    test('treats Windows paths case-insensitively', () {
      expect(
        staleArchives(
          present: ['Actions_Checkout\\AAA.zip'],
          planned: ['actions_checkout\\aaa.zip'],
        ),
        isEmpty,
      );
    });

    test('refuses to sweep the cache on an empty plan', () {
      // "Nothing is planned" and "everything is stale" are the same set, and
      // only one of them is a reason to delete a working cache.
      expect(
        () => staleArchives(present: ['a.zip'], planned: []),
        throwsArgumentError,
      );
    });
  });
}
