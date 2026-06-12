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

    test('a local file announces in any non-error state', () {
      for (final s in [
        PlaybackStatus.loading,
        PlaybackStatus.paused,
        PlaybackStatus.playing,
        PlaybackStatus.ended,
      ]) {
        expect(canAnnounceOnConnect(filePath: file, status: s), isTrue,
            reason: '$s');
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

    test('a URL announces only once it has actually opened', () {
      expect(
        canAnnounceOnConnect(filePath: url, status: PlaybackStatus.loading),
        isFalse,
      );
      expect(
        canAnnounceOnConnect(filePath: url, status: PlaybackStatus.paused),
        isTrue,
      );
      expect(
        canAnnounceOnConnect(filePath: url, status: PlaybackStatus.playing),
        isTrue,
      );
    });
  });
}
