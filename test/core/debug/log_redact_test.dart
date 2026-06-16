import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/log_redact.dart';

void main() {
  group('redactUrls', () {
    test('strips the query string (and any signed token) from a URL', () {
      expect(
        redactUrls('video: mpv error https://cdn.example/clip.mp4?token=abc123&exp=999'),
        'video: mpv error https://cdn.example/clip.mp4',
      );
    });

    test('strips the fragment too', () {
      expect(
        redactUrls('open https://host/path/file.mp4#t=42 done'),
        'open https://host/path/file.mp4 done',
      );
    });

    test('leaves a tokenless URL intact', () {
      expect(
        redactUrls('https://host/path/file.mp4'),
        'https://host/path/file.mp4',
      );
    });

    test('leaves a URL with no query unchanged (no token to strip)', () {
      expect(
        redactUrls('failed at https://host/a.mp4 now'),
        'failed at https://host/a.mp4 now',
      );
    });

    test('redacts multiple URLs in one line', () {
      expect(
        redactUrls('a https://h/x?t=1 b http://h2/y?z=2 c'),
        'a https://h/x b http://h2/y c',
      );
    });

    test('is case-insensitive on the scheme', () {
      expect(redactUrls('HTTPS://H/x?t=1'), 'HTTPS://H/x');
    });

    test('leaves plain text and local paths unchanged', () {
      expect(redactUrls('video: load Episode 3.mkv'), 'video: load Episode 3.mkv');
      expect(
        redactUrls(r'db: recordOpen ok C:\Videos\a.mp4'),
        r'db: recordOpen ok C:\Videos\a.mp4',
      );
    });
  });
}
