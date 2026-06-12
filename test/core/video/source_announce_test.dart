import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/source_announce.dart';

void main() {
  group('canAnnounceOnConnect', () {
    const url = 'https://cdn.example.com/video.mp4';
    const file = r'C:\videos\demo.mkv';

    test('nothing loaded → no announce', () {
      expect(
        canAnnounceOnConnect(filePath: null, status: PlaybackStatus.idle),
        isFalse,
      );
    });

    test('a settled (opened) source announces — local or URL', () {
      for (final path in [file, url]) {
        for (final s in [
          PlaybackStatus.paused,
          PlaybackStatus.playing,
          PlaybackStatus.ended,
        ]) {
          expect(canAnnounceOnConnect(filePath: path, status: s), isTrue,
              reason: '$path / $s');
        }
      }
    });

    test('a not-yet-settled source is NOT announced — local or URL', () {
      // A moved/unreadable local file fails asynchronously the same way a bad
      // link does, so `loading` must be withheld for both.
      for (final path in [file, url]) {
        expect(
          canAnnounceOnConnect(filePath: path, status: PlaybackStatus.loading),
          isFalse,
          reason: '$path loading',
        );
        expect(
          canAnnounceOnConnect(filePath: path, status: PlaybackStatus.idle),
          isFalse,
          reason: '$path idle',
        );
      }
    });

    test('an errored source is never announced (URL or file)', () {
      expect(
        canAnnounceOnConnect(filePath: url, status: PlaybackStatus.error),
        isFalse,
      );
      expect(
        canAnnounceOnConnect(filePath: file, status: PlaybackStatus.error),
        isFalse,
      );
    });
  });
}
