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

  group('peerLoadedUrlJoinPrompt (#121)', () {
    test('offers a one-click load when the peer is watching a URL', () {
      final prompt = peerLoadedUrlJoinPrompt(
        localHasFile: false,
        localUsername: 'meow',
        peerUsername: 'lin',
        peerFileUrl: 'https://cdn.example.com/videos/movie.mp4?token=secret',
      );
      expect(prompt, isNotNull);
      expect(prompt!.message, contains('lin is watching'));
      // Truncated/redacted for display — the query string (and any signed
      // token in it) must never render verbatim in the prompt (mirrors the
      // #116 join-prompt redaction rule).
      expect(prompt.message, contains('cdn.example.com'));
      expect(prompt.message, isNot(contains('token=secret')));
      // The raw URL (needed to actually load it) is kept separately, intact.
      expect(
        prompt.url,
        'https://cdn.example.com/videos/movie.mp4?token=secret',
      );
    });

    test('is null once we have our own file loaded', () {
      expect(
        peerLoadedUrlJoinPrompt(
          localHasFile: true,
          localUsername: 'meow',
          peerUsername: 'lin',
          peerFileUrl: 'https://x.test/a.mp4',
        ),
        isNull,
      );
    });

    test(
      'is null when we already have that exact same URL loaded (#121)',
      () {
        // Same guard as above, spelled out for the specific "already have this
        // link open" case the issue calls out explicitly: localHasFile is
        // true because our own loaded source IS this URL, so no offer.
        expect(
          peerLoadedUrlJoinPrompt(
            localHasFile: true,
            localUsername: 'meow',
            peerUsername: 'lin',
            peerFileUrl: 'https://x.test/a.mp4',
          ),
          isNull,
        );
      },
    );

    test('ignores our own echoed URL announce', () {
      expect(
        peerLoadedUrlJoinPrompt(
          localHasFile: false,
          localUsername: 'meow',
          peerUsername: 'meow',
          peerFileUrl: 'https://x.test/a.mp4',
        ),
        isNull,
      );
    });

    test('is null when the peer file is a local path, not a URL', () {
      expect(
        peerLoadedUrlJoinPrompt(
          localHasFile: false,
          localUsername: 'meow',
          peerUsername: 'lin',
          peerFileUrl: 'movie.mkv',
        ),
        isNull,
      );
    });
  });

  group('peerStartedPlaybackPrompt (#121 follow-up)', () {
    test('keeps the one-click URL when the peer starts playback', () {
      // The play-triggered prompt must not downgrade an active URL offer:
      // the button stays, only the wording moves on to "they started".
      final prompt = peerStartedPlaybackPrompt(
        localHasFile: false,
        localUsername: 'meow',
        peerUsername: 'lin',
        offeredUrl: 'https://x.test/a.mp4?token=secret',
      );
      expect(prompt, isNotNull);
      expect(prompt!.url, 'https://x.test/a.mp4?token=secret');
      expect(prompt.message, contains('lin started playback'));
      // Raw URL (and its token) never leaks into the visible message.
      expect(prompt.message, isNot(contains('token=secret')));
    });

    test('matches the classic #60 text-only prompt when no URL is offered', () {
      final prompt = peerStartedPlaybackPrompt(
        localHasFile: false,
        localUsername: 'meow',
        peerUsername: 'lin',
        offeredUrl: null,
      );
      expect(prompt, isNotNull);
      expect(prompt!.url, isNull);
      expect(
        prompt.message,
        peerStartedPlaybackJoinPrompt(
          localHasFile: false,
          localUsername: 'meow',
          peerUsername: 'lin',
        ),
      );
    });

    test('is null once we have our own file loaded, even with a URL', () {
      expect(
        peerStartedPlaybackPrompt(
          localHasFile: true,
          localUsername: 'meow',
          peerUsername: 'lin',
          offeredUrl: 'https://x.test/a.mp4',
        ),
        isNull,
      );
    });

    test('ignores our own echoed playback, even with a URL', () {
      expect(
        peerStartedPlaybackPrompt(
          localHasFile: false,
          localUsername: 'meow',
          peerUsername: 'meow',
          offeredUrl: 'https://x.test/a.mp4',
        ),
        isNull,
      );
    });
  });
}
