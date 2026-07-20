import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/url_classifier.dart';

void main() {
  group('needsResolver', () {
    test('true for page URLs that are not direct media files', () {
      expect(needsResolver('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          isTrue);
      expect(needsResolver('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(
          needsResolver('https://www.bilibili.com/video/BV1xx411c7mD'), isTrue);
      expect(needsResolver('https://example.com/some/page'), isTrue);
      expect(needsResolver('https://example.com/'), isTrue);
      expect(needsResolver('https://example.com'), isTrue); // no path at all
    });

    test('true for a playlist-style query URL without a media extension', () {
      expect(
        needsResolver(
            'https://www.youtube.com/playlist?list=PL0123456789abcdef'),
        isTrue,
      );
    });

    test('false for direct media file URLs', () {
      expect(needsResolver('https://example.com/video.mp4'), isFalse);
      expect(needsResolver('https://example.com/video.mkv'), isFalse);
      expect(needsResolver('https://example.com/video.webm'), isFalse);
      expect(needsResolver('https://example.com/stream.m3u8'), isFalse);
      expect(needsResolver('https://example.com/seg.ts'), isFalse);
      expect(needsResolver('https://example.com/clip.mov'), isFalse);
      expect(needsResolver('https://example.com/old.avi'), isFalse);
      expect(needsResolver('https://example.com/song.mp3'), isFalse);
      expect(needsResolver('https://example.com/song.m4a'), isFalse);
      expect(needsResolver('https://example.com/song.aac'), isFalse);
      expect(needsResolver('https://example.com/song.flac'), isFalse);
      expect(needsResolver('https://example.com/song.ogg'), isFalse);
      expect(needsResolver('https://example.com/song.opus'), isFalse);
      expect(needsResolver('https://example.com/song.wav'), isFalse);
    });

    test('strips the query string before sniffing the extension', () {
      expect(
        needsResolver('https://cdn.example.com/video.mp4?token=abc&exp=123'),
        isFalse,
      );
      expect(
        needsResolver('https://cdn.example.com/live.m3u8?auth=xyz'),
        isFalse,
      );
    });

    test('extension match is case-insensitive', () {
      expect(needsResolver('https://example.com/VIDEO.MP4'), isFalse);
    });

    test('false for non-http sources (local paths, other schemes)', () {
      expect(needsResolver(r'C:\videos\demo.mp4'), isFalse);
      expect(needsResolver('/home/user/demo.mkv'), isFalse);
      expect(needsResolver('ftp://example.com/page'), isFalse);
      expect(needsResolver('file:///home/user/a.mp4'), isFalse);
      expect(needsResolver('not a url'), isFalse);
      expect(needsResolver(''), isFalse);
    });
  });
}
