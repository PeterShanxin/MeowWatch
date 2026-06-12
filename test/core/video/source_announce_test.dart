import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/source_announce.dart';

void main() {
  group('canAnnounceOnConnect', () {
    const url = 'https://cdn.example.com/video.mp4';
    const file = r'C:\videos\demo.mkv';
    const dur = Duration(minutes: 30);

    PlaybackState st(String? path, PlaybackStatus status, {Duration d = dur}) =>
        PlaybackState(filePath: path, status: status, duration: d);

    test('nothing loaded → no announce', () {
      expect(canAnnounceOnConnect(st(null, PlaybackStatus.idle)), isFalse);
    });

    test('a confirmed open announces — local or URL', () {
      for (final path in [file, url]) {
        expect(canAnnounceOnConnect(st(path, PlaybackStatus.playing)), isTrue);
        expect(canAnnounceOnConnect(st(path, PlaybackStatus.paused)), isTrue);
        expect(canAnnounceOnConnect(st(path, PlaybackStatus.ended)), isTrue);
      }
    });

    test('the transient paused tick (no duration) is NOT announced', () {
      // media_kit emits paused before a failing source errors; with no duration
      // yet, that is not a confirmed open.
      expect(
        canAnnounceOnConnect(
            st(url, PlaybackStatus.paused, d: Duration.zero)),
        isFalse,
      );
      expect(
        canAnnounceOnConnect(
            st(file, PlaybackStatus.paused, d: Duration.zero)),
        isFalse,
      );
    });

    test('loading / idle / error are never announced — local or URL', () {
      for (final path in [file, url]) {
        for (final s in [
          PlaybackStatus.loading,
          PlaybackStatus.idle,
          PlaybackStatus.error,
        ]) {
          expect(canAnnounceOnConnect(st(path, s)), isFalse, reason: '$path/$s');
        }
      }
    });
  });
}
