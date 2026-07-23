import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/mpv_log_filter.dart';

void main() {
  group('formatMpvLogLine', () {
    test('keeps the ffmpeg line that names why an open failed', () {
      // This is the whole point of the listener: media_kit forwards an
      // `ffmpeg` error to its error stream ONLY when the text starts with
      // `tcp:`, so an HTTP status — the one detail that says whether a CDN
      // rejected us or the connection died — never reaches the log (#228).
      expect(
        formatMpvLogLine(
          prefix: 'ffmpeg',
          level: 'error',
          text: 'http: HTTP error 403 Forbidden',
        ),
        'video: mpv[ffmpeg] http: HTTP error 403 Forbidden',
      );
    });

    test('keeps mpv fatal lines too', () {
      expect(
        formatMpvLogLine(prefix: 'cplayer', level: 'fatal', text: 'boom'),
        'video: mpv[cplayer] boom',
      );
    });

    test('drops anything below error', () {
      for (final level in ['warn', 'info', 'v', 'debug', 'trace']) {
        expect(
          formatMpvLogLine(prefix: 'ffmpeg', level: level, text: 'chatter'),
          isNull,
          reason: 'level $level is not a failure',
        );
      }
    });

    test('drops an empty message', () {
      expect(
        formatMpvLogLine(prefix: 'ffmpeg', level: 'error', text: '   '),
        isNull,
      );
    });

    test('redacts a signed stream URL before it reaches disk', () {
      final line = formatMpvLogLine(
        prefix: 'stream',
        level: 'error',
        text: 'Failed to open https://rr4---sn-2o30.googlevideo.com/'
            'videoplayback?expire=123&sig=SECRETTOKEN',
      );
      expect(line, isNotNull);
      expect(line, isNot(contains('SECRETTOKEN')));
      expect(line, contains('googlevideo.com'));
    });
  });
}
