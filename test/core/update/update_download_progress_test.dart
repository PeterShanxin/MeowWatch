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

  group('progress notifications are throttled (#197 P5)', () {
    test('known total: notifies per whole-percent change, not per chunk',
        () async {
      // 500 chunks of 200 bytes = 100 000 bytes. Un-throttled this notifies
      // once per chunk (500×, thousands for a real ~50 MB zip); whole-percent
      // throttling caps it near 100.
      const chunkSize = 200;
      const chunkCount = 500;
      final chunk = List<int>.filled(chunkSize, 42);
      final mock = MockClient.streaming((req, body) async {
        if (req.url.path.endsWith('latest.json')) return json200(latestJson());
        if (req.url.path.endsWith('a.zip')) {
          return http.StreamedResponse(
            Stream.fromIterable(Iterable.generate(chunkCount, (_) => chunk)),
            200,
            contentLength: chunkSize * chunkCount,
          );
        }
        return http.StreamedResponse(Stream.value(<int>[]), 404);
      });
      final svc =
          UpdateService.forTest(baseUrl: 'https://example.test', client: mock);
      addTearDown(svc.dispose);

      expect(await svc.checkForUpdate(), UpdateStatus.updateAvailable);

      var notifications = 0;
      svc.addListener(() {
        if (svc.phase == UpdatePhase.downloading) notifications++;
      });
      await svc.startDownload();

      // At most one per percent, plus the initial phase change — far below
      // one per chunk.
      expect(notifications, lessThanOrEqualTo(110));
      // The dialog still ends on a complete, accurate final state.
      expect(svc.downloadProgress, 1.0);
      expect(svc.downloadReceivedBytes, chunkSize * chunkCount);
    });

    test(
        'unknown total: first chunk notifies for visible motion, then only '
        'every 256 KiB', () async {
      const chunkSize = 1000;
      const chunkCount = 10; // 10 KB total — far below the 256 KiB step.
      final chunk = List<int>.filled(chunkSize, 7);
      final mock = MockClient.streaming((req, body) async {
        if (req.url.path.endsWith('latest.json')) return json200(latestJson());
        if (req.url.path.endsWith('a.zip')) {
          // contentLength omitted → indeterminate download.
          return http.StreamedResponse(
            Stream.fromIterable(Iterable.generate(chunkCount, (_) => chunk)),
            200,
          );
        }
        return http.StreamedResponse(Stream.value(<int>[]), 404);
      });
      final svc =
          UpdateService.forTest(baseUrl: 'https://example.test', client: mock);
      addTearDown(svc.dispose);

      expect(await svc.checkForUpdate(), UpdateStatus.updateAvailable);

      var notifications = 0;
      svc.addListener(() {
        if (svc.phase == UpdatePhase.downloading) notifications++;
      });
      await svc.startDownload();

      // Exactly two: the downloading phase change + the first chunk. The
      // remaining nine chunks fall below the 256 KiB step and are dropped.
      expect(notifications, 2);
      // The byte counter still ends accurate even though notifications were
      // dropped along the way.
      expect(svc.downloadReceivedBytes, chunkSize * chunkCount);
    });
  });
}
