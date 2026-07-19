import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/resolve_error.dart';
import 'package:meowwatch/core/resolve/yt_dlp_resolver.dart';

ProcessResult _ok(Object json) =>
    ProcessResult(1, 0, jsonEncode(json), '');

ProcessResult _fail(String stderr) => ProcessResult(1, 1, '', stderr);

void main() {
  const pageUrl = 'https://www.youtube.com/watch?v=abc';

  group('YtDlpResolver.resolve', () {
    test('builds exactly the fixed yt-dlp arg list', () async {
      String? capturedExe;
      List<String>? capturedArgs;
      final resolver = YtDlpResolver(
        exePath: r'C:\tools\yt-dlp.exe',
        runner: (exe, args) async {
          capturedExe = exe;
          capturedArgs = args;
          return _ok({'url': 'https://cdn.example.com/v'});
        },
      );
      await resolver.resolve(pageUrl);
      expect(capturedExe, r'C:\tools\yt-dlp.exe');
      expect(capturedArgs, [
        '-J',
        '--no-playlist',
        '-I',
        '1',
        '-f',
        'bv*+ba/b',
        '--ignore-config',
        '--no-warnings',
        '--socket-timeout',
        '10',
        '--retries',
        '2',
        '--',
        pageUrl,
      ]);
    });

    test('parses single-format JSON (top-level url + http_headers)', () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({
          'title': 'A single format video',
          'url': 'https://cdn.example.com/direct.mp4',
          'http_headers': {'User-Agent': 'UA', 'Referer': 'https://ex.com/'},
        }),
      );
      final media = await resolver.resolve(pageUrl);
      expect(media.pageUrl, pageUrl);
      expect(media.videoUrl, 'https://cdn.example.com/direct.mp4');
      expect(media.audioUrl, isNull);
      expect(media.httpHeaders,
          {'User-Agent': 'UA', 'Referer': 'https://ex.com/'});
      expect(media.title, 'A single format video');
    });

    test('parses split requested_formats with bilibili-style headers',
        () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({
          'title': 'Bilibili video',
          'requested_formats': [
            {
              'url': 'https://upos.example.com/video.m4s',
              'vcodec': 'avc1.640032',
              'acodec': 'none',
              'http_headers': {
                'Referer': 'https://www.bilibili.com/',
                'User-Agent': 'Mozilla/5.0',
              },
            },
            {
              'url': 'https://upos.example.com/audio.m4s',
              'vcodec': 'none',
              'acodec': 'mp4a.40.2',
              'http_headers': {'Referer': 'https://www.bilibili.com/'},
            },
          ],
        }),
      );
      final media = await resolver.resolve(pageUrl);
      expect(media.videoUrl, 'https://upos.example.com/video.m4s');
      expect(media.audioUrl, 'https://upos.example.com/audio.m4s');
      expect(media.httpHeaders, {
        'Referer': 'https://www.bilibili.com/',
        'User-Agent': 'Mozilla/5.0',
      });
      expect(media.title, 'Bilibili video');
    });

    test('picks the vcodec != none entry as video even when order is swapped',
        () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({
          'requested_formats': [
            {'url': 'https://cdn.example.com/audio', 'vcodec': 'none'},
            {'url': 'https://cdn.example.com/video', 'vcodec': 'vp9'},
          ],
        }),
      );
      final media = await resolver.resolve(pageUrl);
      expect(media.videoUrl, 'https://cdn.example.com/video');
      expect(media.audioUrl, 'https://cdn.example.com/audio');
    });

    test('playlist JSON throws unknown with a playlist detail', () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({
          '_type': 'playlist',
          'entries': <Object>[],
        }),
      );
      await expectLater(
        resolver.resolve(pageUrl),
        throwsA(isA<ResolveException>()
            .having((e) => e.kind, 'kind', ResolveErrorKind.unknown)
            .having((e) => e.detail, 'detail', contains('playlist'))),
      );
    });

    test('exit 1 with DRM stderr throws drm', () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async =>
            _fail('ERROR: this video is DRM protected'),
      );
      await expectLater(
        resolver.resolve(pageUrl),
        throwsA(isA<ResolveException>()
            .having((e) => e.kind, 'kind', ResolveErrorKind.drm)),
      );
    });

    test('runner that never completes throws timeout', () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) => Completer<ProcessResult>().future,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        resolver.resolve(pageUrl),
        throwsA(isA<ResolveException>()
            .having((e) => e.kind, 'kind', ResolveErrorKind.timeout)),
      );
    });

    test('malformed JSON throws unknown', () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => ProcessResult(1, 0, 'not json {', ''),
      );
      await expectLater(
        resolver.resolve(pageUrl),
        throwsA(isA<ResolveException>()
            .having((e) => e.kind, 'kind', ResolveErrorKind.unknown)),
      );
    });

    test('JSON without any stream URL throws unknown', () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({'title': 'no urls here'}),
      );
      await expectLater(
        resolver.resolve(pageUrl),
        throwsA(isA<ResolveException>()
            .having((e) => e.kind, 'kind', ResolveErrorKind.unknown)),
      );
    });

    test('stringifies non-string header values', () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({
          'url': 'https://cdn.example.com/v',
          'http_headers': {'X-Num': 42},
        }),
      );
      final media = await resolver.resolve(pageUrl);
      expect(media.httpHeaders, {'X-Num': '42'});
    });
  });
}
