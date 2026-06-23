import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_support_dir.dart';
import 'package:path/path.dart' as p;

void main() {
  group('resolveAppSupportDir', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('meow_support_test');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('honors the MEOWWATCH_DATA_DIR override', () async {
      final target = p.join(tmp.path, 'dev-data');
      final dir = await resolveAppSupportDir(
        environment: {kDataDirEnvVar: target},
      );
      expect(p.equals(dir.path, target), isTrue);
    });

    test('creates the override directory when missing', () async {
      final target = p.join(tmp.path, 'made', 'on', 'demand');
      expect(Directory(target).existsSync(), isFalse);
      final dir = await resolveAppSupportDir(
        environment: {kDataDirEnvVar: target},
      );
      expect(dir.existsSync(), isTrue);
    });

    test('blank/whitespace override falls through to the platform dir',
        () async {
      // A blank override must not redirect data to a directory named " ".
      // (We can't call the real platform path provider in a unit test, so we
      // only assert the override branch is *not* taken — a blank value must be
      // treated as unset; the fallthrough is exercised in the running app.)
      expect(
        overrideDirFor({kDataDirEnvVar: '   '}),
        isNull,
      );
      expect(overrideDirFor(const {}), isNull);
      expect(overrideDirFor({kDataDirEnvVar: '/some/dir'})?.path, '/some/dir');
    });
  });
}
