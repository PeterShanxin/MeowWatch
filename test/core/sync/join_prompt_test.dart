import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/join_prompt.dart';

/// The empty-screen "load a video to join" prompt shown to whoever hasn't
/// loaded yet. #60 surfaced it on peer playback; #116 also surfaces it the
/// moment a peer announces a loaded file, so a friend who loads but doesn't
/// press play still nudges the other side.
void main() {
  group('peerLoadedJoinPrompt (#116)', () {
    test('names the peer and their file when we have nothing loaded', () {
      expect(
        peerLoadedJoinPrompt(
          localHasFile: false,
          localUsername: 'meow',
          peerUsername: 'lin',
          peerFileName: 'movie.mkv',
        ),
        'lin loaded "movie.mkv" — load the same video to join',
      );
    });

    test('is null once we have our own file loaded', () {
      expect(
        peerLoadedJoinPrompt(
          localHasFile: true,
          localUsername: 'meow',
          peerUsername: 'lin',
          peerFileName: 'movie.mkv',
        ),
        isNull,
      );
    });

    test('ignores our own echoed file announce', () {
      expect(
        peerLoadedJoinPrompt(
          localHasFile: false,
          localUsername: 'meow',
          peerUsername: 'meow',
          peerFileName: 'movie.mkv',
        ),
        isNull,
      );
    });
  });

  group('peerStartedPlaybackJoinPrompt (#60)', () {
    test('names the peer when we have nothing loaded', () {
      expect(
        peerStartedPlaybackJoinPrompt(
          localHasFile: false,
          localUsername: 'meow',
          peerUsername: 'lin',
        ),
        'lin started playback — load a video to join',
      );
    });

    test('is null once we have our own file loaded', () {
      expect(
        peerStartedPlaybackJoinPrompt(
          localHasFile: true,
          localUsername: 'meow',
          peerUsername: 'lin',
        ),
        isNull,
      );
    });

    test('ignores our own echoed activity', () {
      expect(
        peerStartedPlaybackJoinPrompt(
          localHasFile: false,
          localUsername: 'meow',
          peerUsername: 'meow',
        ),
        isNull,
      );
    });
  });
}
