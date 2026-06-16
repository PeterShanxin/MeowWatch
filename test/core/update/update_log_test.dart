import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meowwatch/core/debug/app_log.dart';
import 'package:meowwatch/core/debug/debug_log.dart';
import 'package:meowwatch/core/update/update_service.dart';

/// The update service is a standalone singleton with no [DebugLog] of its own;
/// #140 routes its events through the process-wide [appLog]. Prove a check lands
/// an `update:` line in an installed session log.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('meow_updatelog_test'));
  tearDown(() {
    installAppLog(null);
    dir.deleteSync(recursive: true);
  });

  String readLog() => dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.log'))
      .single
      .readAsStringSync();

  test('checkForUpdate writes a result line to the session log', () async {
    final log = DebugLog.inDir(dir, baseName: 'meowwatch_sync')..start();
    installAppLog(log);

    // An ancient remote version → up to date (never newer than the build).
    final body = jsonEncode({
      'version': '0.0.1',
      'assets': {
        'windows-x64': {'url': 'https://example.test/a.zip', 'sha256': 'x'},
      },
    });
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('latest.json')) return http.Response(body, 200);
      return http.Response('', 404);
    });
    final svc =
        UpdateService.forTest(baseUrl: 'https://example.test', client: mock);

    final status = await svc.checkForUpdate();
    await log.close();

    expect(status, UpdateStatus.upToDate);
    expect(readLog(), contains('update: check remote=0.0.1'));
  });

  test('an early check failure (non-200) is logged', () async {
    final log = DebugLog.inDir(dir, baseName: 'meowwatch_sync')..start();
    installAppLog(log);

    final mock = MockClient((req) async => http.Response('', 503));
    final svc =
        UpdateService.forTest(baseUrl: 'https://example.test', client: mock);

    final status = await svc.checkForUpdate();
    await log.close();

    expect(status, UpdateStatus.checkFailed);
    expect(readLog(), contains('update: check failed (HTTP 503)'));
  });

  test('a thrown check (malformed JSON) logs the failure', () async {
    final log = DebugLog.inDir(dir, baseName: 'meowwatch_sync')..start();
    installAppLog(log);

    // 200 with a non-JSON body → jsonDecode throws → caught and logged.
    final mock = MockClient((req) async => http.Response('not json', 200));
    final svc =
        UpdateService.forTest(baseUrl: 'https://example.test', client: mock);

    final status = await svc.checkForUpdate();
    await log.close();

    expect(status, UpdateStatus.checkFailed);
    expect(readLog(), contains('update: check failed'));
  });
}
