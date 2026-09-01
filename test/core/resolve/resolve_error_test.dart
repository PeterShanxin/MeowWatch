import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/resolve_error.dart';

void main() {
  group('mapYtDlpStderr', () {
    test('maps DRM stderr to drm', () {
      expect(
        mapYtDlpStderr(
            'ERROR: [generic] this video is DRM protected and cannot be '
            'downloaded'),
        ResolveErrorKind.drm,
      );
    });

    test('maps unsupported-site stderr to unsupportedSite', () {
      expect(
        mapYtDlpStderr(
            'ERROR: Unsupported URL: https://example.com/some/page'),
        ResolveErrorKind.unsupportedSite,
      );
    });

    test('maps geo-restriction stderr to geoBlocked', () {
      expect(
        mapYtDlpStderr('ERROR: [youtube] abc: This video is not available in '
            'your country'),
        ResolveErrorKind.geoBlocked,
      );
      expect(
        mapYtDlpStderr('ERROR: might be caused by geo restriction'),
        ResolveErrorKind.geoBlocked,
      );
    });

    test('maps unavailable-video stderr to unavailable', () {
      expect(
        mapYtDlpStderr('ERROR: [youtube] abc: Private video. Sign in if you '
            'have been granted access'),
        ResolveErrorKind.unavailable,
      );
      expect(
        mapYtDlpStderr('ERROR: [youtube] abc: Video unavailable'),
        ResolveErrorKind.unavailable,
      );
      expect(
        mapYtDlpStderr('ERROR: Sign in to confirm your age'),
        ResolveErrorKind.unavailable,
      );
    });

    test('maps network stderr to network', () {
      expect(
        mapYtDlpStderr('ERROR: Unable to download webpage: <urlopen error '
            '[Errno 11001] getaddrinfo failed>'),
        ResolveErrorKind.network,
      );
      expect(
        mapYtDlpStderr('ERROR: Unable to download API page: The read '
            'operation timed out'),
        ResolveErrorKind.network,
      );
      expect(
        mapYtDlpStderr('ERROR: <urlopen error [WinError 10060] A connection '
            'attempt failed>'),
        ResolveErrorKind.network,
      );
    });

    test('drm wins over later categories when both markers appear', () {
      expect(
        mapYtDlpStderr('ERROR: Unable to download: DRM protected content'),
        ResolveErrorKind.drm,
      );
    });

    test('matching is case-sensitive', () {
      expect(
        mapYtDlpStderr('ERROR: drm protected'), // lowercase — not the marker
        ResolveErrorKind.unknown,
      );
    });

    test('unrecognized stderr falls through to unknown', () {
      expect(mapYtDlpStderr('ERROR: something novel went wrong'),
          ResolveErrorKind.unknown);
      expect(mapYtDlpStderr(''), ResolveErrorKind.unknown);
    });
  });

  group('friendlyResolveError', () {
    test('has non-empty, user-facing copy for every kind', () {
      for (final kind in ResolveErrorKind.values) {
        final copy = friendlyResolveError(kind);
        expect(copy, isNotEmpty, reason: '$kind');
        expect(copy.contains('ERROR'), isFalse, reason: '$kind');
        expect(copy.contains('yt-dlp'), isFalse, reason: '$kind');
      }
    });

    test('drm copy matches the planned wording', () {
      expect(
        friendlyResolveError(ResolveErrorKind.drm),
        "This site protects its videos, so they can't be played here.",
      );
    });

    test('unsupportedOnThisOs tells testers to load a file or direct link', () {
      final copy = friendlyResolveError(ResolveErrorKind.unsupportedOnThisOs);
      expect(copy.toLowerCase(), contains('windows'));
      expect(copy.toLowerCase(), contains('file'));
    });
  });

  group('ResolveException', () {
    test('carries kind and detail and prints both', () {
      const e = ResolveException(ResolveErrorKind.timeout, 'took too long');
      expect(e.kind, ResolveErrorKind.timeout);
      expect(e.detail, 'took too long');
      expect(e.toString(), contains('timeout'));
      expect(e.toString(), contains('took too long'));
    });
  });
}
