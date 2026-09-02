import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/action_cache.dart';

void main() {
  late Map<String, List<String>> jobs;

  setUpAll(() {
    jobs = splitWorkflowJobs(
      File('.github/workflows/build.yml').readAsStringSync(),
    );
  });

  String jobText(String name) {
    final block = jobs[name];
    expect(block, isNotNull, reason: 'missing job $name');
    return block!.join('\n');
  }

  test('PR and self-hosted analyze jobs do not interpolate signing or R2 secrets', () {
    for (final name in ['check-self-hosted', 'check-hosted', 'gate']) {
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
    expect(text, contains('secrets.MEOWWATCH_RELEASE_KEY'));
    expect(text, contains('subosito/flutter-action@v2'));
    expect(text, isNot(contains('self-hosted')));
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
