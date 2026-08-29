import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/action_cache.dart';

const _trusted = ['PeterShanxin', 'ianmeowmeow'];
const _privilegedSecrets = [
  r'${{ secrets.R2_',
  r'${{ secrets.RELEASE_MIRROR_TOKEN',
  r'.meowwatch\release-key.txt',
  '.meowwatch/release-key.txt',
];

void main() {
  late String workflow;
  late Map<String, List<String>> jobs;

  setUpAll(() {
    workflow = File('.github/workflows/build.yml').readAsStringSync();
    jobs = splitWorkflowJobs(workflow);
  });

  String jobText(String name) => jobs[name]!.join('\n');

  String? foldIf(List<String> jobLines) {
    for (var index = 0; index < jobLines.length; index += 1) {
      final match = RegExp(r'^(\s*)if:\s*(.*)$').firstMatch(jobLines[index]);
      if (match == null) continue;
      final inline = match.group(2)!.trim();
      if (inline.isNotEmpty && !const ['>-', '>', '|'].contains(inline)) {
        return inline;
      }
      final indent = match.group(1)!.length;
      final collected = <String>[];
      for (var next = index + 1; next < jobLines.length; next += 1) {
        final line = jobLines[next];
        if (line.trim().isEmpty) continue;
        if (_indentOf(line) <= indent) break;
        collected.add(line.trim());
      }
      return collected.join(' ');
    }
    return null;
  }

  bool hasContentsReadOnly(List<String> jobLines) {
    final text = jobLines.join('\n');
    return text.contains('contents: read') && !text.contains('contents: write');
  }

  group('build.yml Stage 2 CI', () {
    test('declares the jobs the merge gate and tag path need', () {
      expect(
        jobs.keys,
        containsAll([
          'check-self-hosted',
          'check-hosted',
          'gate',
          'build-windows-x64',
          'release',
        ]),
      );
    });

    test('pull_request cannot queue on meowwatch-ci', () {
      for (final entry in jobs.entries) {
        final runsOn = foldRunsOn(entry.value) ?? '';
        if (!runsOn.contains('meowwatch-ci')) continue;
        final condition = foldIf(entry.value) ?? '';
        expect(
          condition,
          contains("github.event_name != 'pull_request'"),
          reason:
              '${entry.key} runs on meowwatch-ci but its if: can still be '
              'true for pull_request, so GitHub would queue it on that host.',
        );
      }
    });

    test('every pull_request takes check-hosted on windows-2025', () {
      expect(foldRunsOn(jobs['check-hosted']!), 'windows-2025');
      expect(
        foldIf(jobs['check-hosted']!),
        contains("github.event_name == 'pull_request'"),
      );
      expect(
        foldIf(jobs['check-hosted']!),
        isNot(contains('PeterShanxin')),
        reason:
            'Owner/ianmeowmeow must not be carved out of check-hosted; '
            'every PR uses hosted Windows.',
      );
    });

    test('hosted PR jobs stay contents: read and omit privileged secrets', () {
      for (final name in ['check-hosted', 'gate']) {
        expect(hasContentsReadOnly(jobs[name]!), isTrue, reason: name);
        final text = jobText(name);
        for (final secret in _privilegedSecrets) {
          expect(text, isNot(contains(secret)), reason: '$name $secret');
        }
      }
    });

    test('gate is still Analyze & Test and requires hosted green', () {
      expect(jobText('gate'), contains('name: Analyze & Test'));
      expect(jobText('gate'), contains('needs.check-hosted.result'));
      expect(
        jobText('gate'),
        contains('[ "\$ho" = "success" ]'),
      );
    });

    test('remaining self-hosted jobs keep the two-actor allowlist', () {
      for (final name in ['check-self-hosted', 'build-windows-x64']) {
        final text = jobText(name);
        expect(foldRunsOn(jobs[name]!), contains('meowwatch-ci'));
        expect(text, contains('Refuse untrusted workflow actors'));
        expect(
          text,
          contains("uses: actions/checkout@v7"),
        );
        expect(
          text.indexOf('Refuse untrusted workflow actors'),
          lessThan(text.indexOf('uses: actions/checkout@v7')),
          reason: '$name must fail closed before checkout',
        );
        expect(foldIf(jobs[name]!), contains('github.actor'));
        for (final login in _trusted) {
          expect(text, contains("'$login'"));
        }
        expect(text, contains('PR_USER'));
        expect(text, contains('ianmeowmeow'));
      }
    });

    test('tag signing stays on self-hosted and still reads the seed there', () {
      final text = jobText('build-windows-x64');
      expect(text, contains('Sign release'));
      expect(text, contains(r".meowwatch\release-key.txt"));
      expect(foldIf(jobs['build-windows-x64']!), contains("refs/tags/v"));
    });
  });
}

int _indentOf(String line) => line.length - line.trimLeft().length;
