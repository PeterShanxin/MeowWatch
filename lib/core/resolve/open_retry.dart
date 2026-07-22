import '../video/playback_state.dart';

/// Shown over the load screen while the second resolve runs, so the retry reads
/// as the app handling it rather than as a stall.
const String kResolvedOpenRetryNotice =
    'That link went stale — fetching a fresh one…';

/// Whether a load that failed to open should be retried once against a freshly
/// resolved stream URL (#228).
///
/// yt-dlp hands back a signed, short-lived, edge-specific CDN link. It resolves
/// cleanly and then mpv's open of it is rejected within a second — roughly one
/// paste in three during manual testing. Investigation ruled out the obvious
/// culprits: the same link fetched outside the app returned `206` on every
/// attempt (with and without yt-dlp's headers, including the exact CDN hosts
/// that had failed), and nothing in our path mangles the signed query — Dart's
/// URI normalization left all of them byte-identical. What actually clears it
/// is a *fresh resolve*, which is what the user was doing by hand with **Try
/// again**. So the app does it instead.
///
/// The conditions are deliberately narrow:
/// - [wasResolved] — only a page URL has a fresher link to fetch. Retrying a
///   local file or a direct stream URL would just repeat the same failing open.
/// - [alreadyRetried] — once. A second failure is a real failure and the user
///   should see it rather than watch the app loop.
/// - [status] — only [PlaybackStatus.error], mpv rejecting the source. A load
///   that merely timed out was reachable but never decoded; re-resolving buys
///   another full resolve plus another 12s wait to reach the same stall.
bool shouldRetryResolvedOpen({
  required bool wasResolved,
  required bool alreadyRetried,
  required PlaybackStatus status,
}) =>
    wasResolved && !alreadyRetried && status == PlaybackStatus.error;
