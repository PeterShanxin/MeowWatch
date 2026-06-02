import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meowwatch/core/update/update_service.dart';

void main() {
  String latestJson() => jsonEncode({
        'version': '99.0.0',
        'assets': {
          'windows-x64': {'url': 'https://example.test/a.zip', 'sha256': null},
          'windows-arm64': {'url': 'https://example.test/a.zip', 'sha256': null},
        },
      });

  http.StreamedResponse json200(String body) =>
      http.StreamedResponse(Stream.value(utf8.encode(body)), 200);

  test('no Content-Length → stays indeterminate, still reports received bytes '
      '(#63)', () async {
    final data = List<int>.generate(2000, (i) => i % 256);
    final mock = MockClient.streaming((req, body) async {
      if (req.url.path.endsWith('latest.json')) return json200(latestJson());
      if (req.url.path.endsWith('a.zip')) {
        // contentLength omitted → null, like an R2/CDN chunked response.
        return http.StreamedResponse(
          Stream.fromIterable([data.sublist(0, 1000), data.sublist(1000)]),
          200,
        );
      }
      return http.StreamedResponse(Stream.value(<int>[]), 404);
    });
    final svc =
        UpdateService.forTest(baseUrl: 'https://example.test', client: mock);
    addTearDown(svc.dispose);

    expect(await svc.checkForUpdate(), UpdateStatus.updateAvailable);

    // Capture every progress value reported while downloading.
    final progresses = <double>[];
    svc.addListener(() {
      if (svc.phase == UpdatePhase.downloading) {
        progresses.add(svc.downloadProgress);
      }
    });

    await svc.startDownload();

    expect(svc.phase, UpdatePhase.readyToInstall);
    expect(svc.hasDownloadTotal, isFalse);
    expect(svc.downloadReceivedBytes, 2000);
    // Never reports a fake fraction — progress stays 0 so the UI knows to show
    // an indeterminate bar instead of a frozen 0%.
    expect(progresses.every((p) => p == 0), isTrue);
  });

  test('known Content-Length → determinate progress reaches 1.0 (#63)',
      () async {
    final data = List<int>.filled(1000, 7);
    final mock = MockClient.streaming((req, body) async {
      if (req.url.path.endsWith('latest.json')) return json200(latestJson());
      if (req.url.path.endsWith('a.zip')) {
        return http.StreamedResponse(
          Stream.fromIterable([data.sublist(0, 400), data.sublist(400)]),
          200,
          contentLength: 1000,
        );
      }
      return http.StreamedResponse(Stream.value(<int>[]), 404);
    });
    final svc =
        UpdateService.forTest(baseUrl: 'https://example.test', client: mock);
    addTearDown(svc.dispose);

    expect(await svc.checkForUpdate(), UpdateStatus.updateAvailable);
    await svc.startDownload();

    expect(svc.hasDownloadTotal, isTrue);
    expect(svc.downloadTotalBytes, 1000);
    expect(svc.downloadReceivedBytes, 1000);
    expect(svc.downloadProgress, 1.0);
  });
}
