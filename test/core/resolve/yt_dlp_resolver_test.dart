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
      // The audio stream carries its own headers so the CDN doesn't 403 it.
      expect(media.audioHeaders, {'Referer': 'https://www.bilibili.com/'});
      expect(media.title, 'Bilibili video');
    });

    test('audio headers fall back to the video headers when absent', () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({
          'requested_formats': [
            {
              'url': 'https://cdn.example.com/video',
              'vcodec': 'vp9',
              'http_headers': {'Referer': 'https://site/'},
            },
            {'url': 'https://cdn.example.com/audio', 'vcodec': 'none'},
          ],
        }),
      );
      final media = await resolver.resolve(pageUrl);
      expect(media.audioHeaders, {'Referer': 'https://site/'});
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

    test('empty playlist JSON throws unknown with a playlist detail', () async {
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

    test('single-entry playlist (series /play/ URL) resolves the entry',
        () async {
      // bilibili.tv /play/<id> and other series/episode pages come back as a
      // one-entry playlist even under --no-playlist; the entry itself carries
      // the real split video+audio formats with CDN headers.
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({
          '_type': 'playlist',
          'title': 'A Series',
          'entries': [
            {
              'title': 'E1 - Conviction',
              'requested_formats': [
                {
                  'vcodec': 'hev1.1',
                  'acodec': 'none',
                  'url': 'https://cdn.bstar/v.m4s',
                  'http_headers': {'Referer': 'https://www.bilibili.tv/'},
                },
                {
                  'vcodec': 'none',
                  'acodec': 'mp4a.40.2',
                  'url': 'https://cdn.bstar/a.m4s',
                  'http_headers': {'Referer': 'https://www.bilibili.tv/'},
                },
              ],
            },
          ],
        }),
      );
      final media = await resolver.resolve(pageUrl);
      expect(media.videoUrl, 'https://cdn.bstar/v.m4s');
      expect(media.audioUrl, 'https://cdn.bstar/a.m4s');
      expect(media.httpHeaders['Referer'], 'https://www.bilibili.tv/');
      // Prefers the entry's own title over the playlist title.
      expect(media.title, 'E1 - Conviction');
      // The page URL the room shares stays the pasted one, never a stream URL.
      expect(media.pageUrl, pageUrl);
    });

    test('playlist whose first entry has no playable stream throws unknown',
        () async {
      final resolver = YtDlpResolver(
        exePath: 'yt-dlp',
        runner: (_, _) async => _ok({
          '_type': 'playlist',
          'entries': [
            {'title': 'no formats'},
          ],
        }),
      );
      await expectLater(
        resolver.resolve(pageUrl),
        throwsA(isA<ResolveException>()
            .having((e) => e.kind, 'kind', ResolveErrorKind.unknown)),
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
