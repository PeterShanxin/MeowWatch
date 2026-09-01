import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/video_url.dart';

void main() {
  group('isHttpUrl', () {
    test('accepts http and https links with a host', () {
      expect(isHttpUrl('http://example.com/video.mp4'), isTrue);
      expect(isHttpUrl('https://example.com/stream.m3u8'), isTrue);
      expect(isHttpUrl('  https://example.com/a.mp4  '), isTrue); // trimmed
      expect(isHttpUrl('HTTPS://Example.com/a.mp4'.toLowerCase()), isTrue);
    });

    test('rejects non-http schemes, hostless URLs, and local paths', () {
      expect(isHttpUrl('http://'), isFalse); // no host
      expect(isHttpUrl('ftp://example.com/a.mp4'), isFalse);
      expect(isHttpUrl('file:///home/user/a.mp4'), isFalse);
      expect(isHttpUrl(r'C:\videos\demo.mp4'), isFalse);
      expect(isHttpUrl('/home/user/demo.mp4'), isFalse);
      expect(isHttpUrl('example.com/a.mp4'), isFalse); // no scheme
      expect(isHttpUrl(''), isFalse);
    });
  });

  group('videoUrlError', () {
    test('returns null for a valid link', () {
      expect(videoUrlError('https://example.com/video.mp4'), isNull);
      expect(videoUrlError('  https://example.com/video.mp4 '), isNull);
    });

    test('flags an empty entry', () {
      expect(videoUrlError(''), isNotNull);
      expect(videoUrlError('   '), isNotNull);
    });

    test('flags something that is not an http(s) link', () {
      expect(videoUrlError('not a url'), isNotNull);
      expect(videoUrlError('ftp://example.com/a.mp4'), isNotNull);
      expect(videoUrlError(r'C:\videos\demo.mp4'), isNotNull);
    });
  });

  group('mediaSourceName', () {
    test('keeps the whole URL as the name (Syncplay convention)', () {
      expect(
        mediaSourceName('https://example.com/path/video.mp4?token=abc'),
        'https://example.com/path/video.mp4?token=abc',
      );
      expect(mediaSourceName('  https://example.com/a.mp4 '),
          'https://example.com/a.mp4');
    });

    test('uses the base filename for a local path', () {
      expect(mediaSourceName('/home/user/clips/demo.mp4'), 'demo.mp4');
      // `package:path` uses this host's separators, so a `C:\…` path is
      // only a basename on Windows. PR CI stays on windows-2022.
      if (Platform.isWindows) {
        expect(mediaSourceName(r'C:\videos\demo.mkv'), 'demo.mkv');
      }
    });
  });

  group('mediaDisplayName', () {
    test('shortens a URL to host/…/file, dropping the query string', () {
      expect(
        mediaDisplayName('https://cdn.example.com/a/b/video.mp4?token=secret'),
        'cdn.example.com/…/video.mp4',
      );
    });

    test('a single-segment URL keeps host/file', () {
      expect(
        mediaDisplayName('https://example.com/video.mp4'),
        'example.com/video.mp4',
      );
    });

    test('a path-less URL falls back to the host', () {
      expect(mediaDisplayName('https://example.com'), 'example.com');
      expect(mediaDisplayName('https://example.com/'), 'example.com');
    });

    test('a local path is left as its basename', () {
      expect(mediaDisplayName('/home/user/clips/demo.mp4'), 'demo.mp4');
      if (Platform.isWindows) {
        expect(mediaDisplayName(r'C:\videos\demo.mkv'), 'demo.mkv');
      }
    });
  });

  group('friendlyPlaybackError', () {
    test('wording differs for a URL vs a local file', () {
      final url = friendlyPlaybackError(isUrl: true);
      final file = friendlyPlaybackError(isUrl: false);
      expect(url, contains('link'));
      expect(file, isNot(contains('link')));
      expect(url, isNotEmpty);
      expect(file, isNotEmpty);
    });
  });

  group('shortPlaybackError', () {
    test('fits one banner row and still says what failed (#232)', () {
      final url = shortPlaybackError(isUrl: true);
      final file = shortPlaybackError(isUrl: false);
      expect(url, contains('link'));
      expect(file, isNot(contains('link')));
      // The banner is a single row — keep it far shorter than the surface copy.
      expect(url.length, lessThan(friendlyPlaybackError(isUrl: true).length));
      expect(file.length, lessThan(friendlyPlaybackError(isUrl: false).length));
      expect(url, isNot(contains('\n')));
      expect(file, isNot(contains('\n')));
    });
  });
}
