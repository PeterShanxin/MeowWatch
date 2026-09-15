import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, List<String>> splitWorkflowJobs(String contents) {
  final lines = contents.split(RegExp(r'\r?\n'));
  final jobsIndex = lines.indexWhere((line) => line.trim() == 'jobs:');
  if (jobsIndex == -1) return <String, List<String>>{};

  final jobs = <String, List<String>>{};
  List<String>? current;
  for (final line in lines.skip(jobsIndex + 1)) {
    if (line.isNotEmpty && !line.startsWith(' ')) break;
    final header = RegExp(r'^  ([A-Za-z_][\w.-]*):\s*$').firstMatch(line);
    if (header != null) {
      current = <String>[];
      jobs[header.group(1)!] = current;
      continue;
    }
    current?.add(line);
  }
  return jobs;
}

void main() {
  late String workflow;
  late Map<String, List<String>> jobs;

  setUpAll(() {
    workflow = File('.github/workflows/build.yml').readAsStringSync();
    jobs = splitWorkflowJobs(workflow);
  });
  String jobText(String name) {
    final block = jobs[name];
    expect(block, isNotNull, reason: 'missing job $name');
    return block!.join('\n');
  }

  test('canonical workflow has no self-hosted CI path', () {
    expect(workflow, isNot(contains('self-hosted')));
    expect(workflow, isNot(contains('meowwatch-ci')));
    expect(workflow, isNot(contains('check-self-hosted')));
    expect(jobs.containsKey('check-self-hosted'), isFalse);
  });

  test('PR jobs do not interpolate signing or R2 secrets', () {
    for (final name in ['check-hosted', 'gate']) {
      final text = jobText(name);
      expect(text, isNot(contains('secrets.MEOWWATCH_RELEASE_KEY')));
      expect(text, isNot(contains('secrets.R2_')));
      expect(text, isNot(contains('contents: write')));
    }
  });

  test('tag Windows job is hosted and signs from the release secret', () {
    final text = jobText('build-windows-x64');
    expect(text, contains('windows-2022'));
    expect(text, contains('environment: release'));
    expect(text, contains('github.event.repository.fork == false'));
    expect(text, contains('secrets.MEOWWATCH_RELEASE_KEY'));
    expect(text, contains('subosito/flutter-action@v2'));
    expect(text, isNot(contains('secrets.R2_')));
    expect(text, contains('contents: write'));
  });
  test('R2 publish interpolates R2 secrets and not the signing seed', () {
    final text = jobText('release');
    expect(text, contains('secrets.R2_'));
    expect(text, isNot(contains('secrets.MEOWWATCH_RELEASE_KEY')));
    expect(text, isNot(contains('contents: write')));
  });
}
