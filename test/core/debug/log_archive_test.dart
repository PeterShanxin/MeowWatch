import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/log_archive.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('meow_logzip'));
  tearDown(() => dir.deleteSync(recursive: true));

  String path(String name) => '${dir.path}${Platform.pathSeparator}$name';

  test('returns null when the directory does not exist', () {
    final missing = Directory(path('does_not_exist'));
    expect(zipLogFiles(missing), isNull);
  });

  test('returns null when the directory holds no .log files', () {
    File(path('readme.txt')).writeAsStringSync('not a log');
    expect(zipLogFiles(dir), isNull);
  });

  test('zips every .log file and skips non-logs', () {
    File(path('a.log')).writeAsStringSync('alpha');
    File(path('b.log')).writeAsStringSync('bravo');
    File(path('notes.txt')).writeAsStringSync('ignore me');

    final bytes = zipLogFiles(dir);
    expect(bytes, isNotNull);

    final archive = ZipDecoder().decodeBytes(bytes!);
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, <String>{'a.log', 'b.log'});

    final a = archive.findFile('a.log')!;
    expect(utf8.decode(a.content as List<int>), 'alpha');
  });

  test(
      'zipLogFilesInBackground zips off the UI isolate and matches the sync '
      'result (#197 P4)', () async {
    File(path('a.log')).writeAsStringSync('alpha');
    File(path('notes.txt')).writeAsStringSync('ignore me');

    final bytes = await zipLogFilesInBackground(dir.path);
    expect(bytes, isNotNull);

    final archive = ZipDecoder().decodeBytes(bytes!);
    expect(archive.files.map((f) => f.name).toSet(), <String>{'a.log'});
    expect(
      utf8.decode(archive.findFile('a.log')!.content as List<int>),
      'alpha',
    );
  });

  test('zipLogFilesInBackground returns null for a missing directory',
      () async {
    expect(await zipLogFilesInBackground(path('does_not_exist')), isNull);
  });
}
