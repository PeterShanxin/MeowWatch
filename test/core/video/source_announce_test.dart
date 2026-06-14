import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/source_announce.dart';

void main() {
  group('canAnnounceOnConnect', () {
    const url = 'https://cdn.example.com/video.mp4';

    test('nothing loaded / nothing accepted → no announce', () {
      expect(
        canAnnounceOnConnect(
          currentPath: null,
          acceptedPath: null,
          status: PlaybackStatus.idle,
        ),
        isFalse,
      );
    });

    test('the accepted, current source announces', () {
      expect(
        canAnnounceOnConnect(
          currentPath: url,
          acceptedPath: url,
          status: PlaybackStatus.paused,
        ),
        isTrue,
      );
    });

    test('a valid live stream (paused, no duration) still announces once '
        'accepted', () {
      // The whole point of tracking the accepted path: bare state can't tell
      // this apart from the pre-error paused tick, but the accepted marker can.
      expect(
        canAnnounceOnConnect(
          currentPath: url,
          acceptedPath: url,
          status: PlaybackStatus.paused,
        ),
        isTrue,
      );
    });

    test('a not-yet-accepted source is withheld (paused tick / loading)', () {
      expect(
        canAnnounceOnConnect(
          currentPath: url,
          acceptedPath: null,
          status: PlaybackStatus.paused,
        ),
        isFalse,
      );
      expect(
        canAnnounceOnConnect(
          currentPath: url,
          acceptedPath: null,
          status: PlaybackStatus.loading,
        ),
        isFalse,
      );
    });

    test('a newer source supersedes the accepted one', () {
      expect(
        canAnnounceOnConnect(
          currentPath: 'https://cdn.example.com/new.mp4',
          acceptedPath: url,
          status: PlaybackStatus.paused,
        ),
        isFalse,
      );
    });

    test('an accepted source that later errored is not announced', () {
      expect(
        canAnnounceOnConnect(
          currentPath: url,
          acceptedPath: url,
          status: PlaybackStatus.error,
        ),
        isFalse,
      );
    });
  });
}
