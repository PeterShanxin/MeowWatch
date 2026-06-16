import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/app_log.dart';
import 'package:meowwatch/core/debug/debug_log.dart';
import 'package:meowwatch/core/debug/log_level.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('meow_applog_test'));
  tearDown(() {
    installAppLog(null); // don't leak a sink into the next test
    dir.deleteSync(recursive: true);
  });

  List<File> logsIn(Directory d) => d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.log'))
      .toList();

  test('appLog is a silent no-op when nothing is installed', () {
    installAppLog(null);
    expect(() => appLog('life: orphan line'), returnsNormally);
    expect(appLogInstance, isNull);
  });

  test('appLog forwards to the installed log', () async {
    final log = DebugLog.inDir(dir, baseName: 'meowwatch_sync')..start();
    installAppLog(log);
    expect(appLogInstance, same(log));

    appLog('life: app start');
    await log.close();

    expect(logsIn(dir).single.readAsStringSync(), contains('life: app start'));
  });

  test('installAppLog(null) detaches the sink so later lines drop', () async {
    final log = DebugLog.inDir(dir, baseName: 'meowwatch_sync')..start();
    installAppLog(log);
    appLog('life: kept');
    installAppLog(null);
    appLog('life: dropped');
    await log.close();

    final text = logsIn(dir).single.readAsStringSync();
    expect(text, contains('life: kept'));
    expect(text, isNot(contains('life: dropped')));
  });

  test('neat level keeps app events but drops trace lines through appLog', () async {
    final log = DebugLog.inDir(dir, baseName: 'meowwatch_sync', level: LogLevel.neat)
      ..start();
    installAppLog(log);
    appLog('video: load Episode.mkv'); // meaningful → kept
    appLog('trace: play'); // firehose → dropped at neat
    await log.close();

    final text = logsIn(dir).single.readAsStringSync();
    expect(text, contains('video: load Episode.mkv'));
    expect(text, isNot(contains('trace: play')));
  });
}
