import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/open_retry.dart';
import 'package:meowwatch/core/video/playback_state.dart';

void main() {
  group('shouldRetryResolvedOpen', () {
    test('retries a resolved page URL that mpv rejected', () {
      expect(
        shouldRetryResolvedOpen(
          wasResolved: true,
          alreadyRetried: false,
          status: PlaybackStatus.error,
        ),
        isTrue,
      );
    });

    test('does not retry a local file or a direct stream URL', () {
      // Nothing was resolved, so there is no fresher URL to fetch — a retry
      // would just repeat the identical failing open.
      expect(
        shouldRetryResolvedOpen(
          wasResolved: false,
          alreadyRetried: false,
          status: PlaybackStatus.error,
        ),
        isFalse,
      );
    });

    test('retries at most once', () {
      expect(
        shouldRetryResolvedOpen(
          wasResolved: true,
          alreadyRetried: true,
          status: PlaybackStatus.error,
        ),
        isFalse,
      );
    });

    test('does not retry a load that timed out rather than erroring', () {
      // A timeout means the stream was reachable but never produced decodable
      // data; re-resolving costs the user another full resolve + 12s wait to
      // land on the same stall. Only a hard rejection gets the fresh link.
      for (final status in [
        PlaybackStatus.loading,
        PlaybackStatus.paused,
        PlaybackStatus.playing,
      ]) {
        expect(
          shouldRetryResolvedOpen(
            wasResolved: true,
            alreadyRetried: false,
            status: status,
          ),
          isFalse,
          reason: 'status $status is not a rejection',
        );
      }
    });
  });

  test('the retry notice names the link, not the machinery', () {
    // Shown over the video while the second resolve runs; it has to read as
    // "we are handling it", not as an error the user must act on.
    expect(kResolvedOpenRetryNotice, isNotEmpty);
    expect(kResolvedOpenRetryNotice.toLowerCase(), contains('link'));
  });
}
