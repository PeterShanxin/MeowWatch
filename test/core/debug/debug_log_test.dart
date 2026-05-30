import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/debug_log.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('meow_log_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes timestamped lines that survive close', () async {
    final file = File('${dir.path}${Platform.pathSeparator}a.log');
    final log = DebugLog(file)..start();
    log('>> hello');
    log('<< world');
    await log.close();

    final text = file.readAsStringSync();
    expect(text, contains('>> hello'));
    expect(text, contains('<< world'));
    // ISO-8601 timestamp prefix on each line.
    expect(RegExp(r'\d{4}-\d{2}-\d{2}T').hasMatch(text), isTrue);
  });

  test('start truncates a previous run', () async {
    final file = File('${dir.path}${Platform.pathSeparator}b.log')
      ..writeAsStringSync('STALE CONTENT FROM LAST RUN');
    final log = DebugLog(file)..start();
    log('fresh');
    await log.close();

    final text = file.readAsStringSync();
    expect(text, isNot(contains('STALE CONTENT')));
    expect(text, contains('fresh'));
  });

  test('logging before start is a silent no-op', () {
    final file = File('${dir.path}${Platform.pathSeparator}c.log');
    // Never started — must not throw, must not create content.
    expect(() => DebugLog(file)('orphan line'), returnsNormally);
    expect(file.existsSync(), isFalse);
  });
}
