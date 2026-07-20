/// Error taxonomy for the yt-dlp resolve path: a small enum of causes, a
/// stderr → cause mapper, and the friendly copy shown to the user. Kept pure
/// so every branch is unit-testable without spawning a process.
library;

/// Why a page-URL resolve failed.
enum ResolveErrorKind {
  /// yt-dlp could not be provisioned (download failed, missing exe).
  toolMissing,

  /// yt-dlp does not know how to extract from this site.
  unsupportedSite,

  /// The video is DRM-protected and cannot be extracted.
  drm,

  /// The video is not available from this region.
  geoBlocked,

  /// Private, deleted, or login-gated video.
  unavailable,

  /// A network problem while yt-dlp talked to the site.
  network,

  /// The resolve took longer than the app-side hard limit.
  timeout,

  /// Anything we could not classify.
  unknown,
}

/// A resolve failure with its classified [kind] and a raw [detail] string
/// (stderr excerpt or parse context) for logs — never shown verbatim to users.
class ResolveException implements Exception {
  const ResolveException(this.kind, this.detail);

  final ResolveErrorKind kind;
  final String detail;

  @override
  String toString() => 'ResolveException(${kind.name}): $detail';
}

/// Classify raw yt-dlp [stderr] output by its documented error markers.
///
/// Substring matches are case-sensitive (the markers are verbatim yt-dlp
/// strings) and checked in fixed priority order:
/// drm → unsupported → geo → unavailable → network → unknown.
ResolveErrorKind mapYtDlpStderr(String stderr) {
  if (stderr.contains('DRM protected')) return ResolveErrorKind.drm;
  if (stderr.contains('Unsupported URL')) {
    return ResolveErrorKind.unsupportedSite;
  }
  if (stderr.contains('geo restriction') ||
      stderr.contains('available in your country')) {
    return ResolveErrorKind.geoBlocked;
  }
  if (stderr.contains('Private video') ||
      stderr.contains('Video unavailable') ||
      stderr.contains('Sign in')) {
    return ResolveErrorKind.unavailable;
  }
  if (stderr.contains('Unable to download') ||
      stderr.contains('timed out') ||
      stderr.contains('getaddrinfo') ||
      stderr.contains('WinError')) {
    return ResolveErrorKind.network;
  }
  return ResolveErrorKind.unknown;
}

/// Short, plain-language copy for [kind], shown on the video error surface.
String friendlyResolveError(ResolveErrorKind kind) {
  switch (kind) {
    case ResolveErrorKind.toolMissing:
      return "The video finder isn't set up yet. Check your connection and "
          'try again.';
    case ResolveErrorKind.unsupportedSite:
      return "This site isn't supported yet. Try a direct video link instead.";
    case ResolveErrorKind.drm:
      return "This site protects its videos, so they can't be played here.";
    case ResolveErrorKind.geoBlocked:
      return "This video isn't available in your region.";
    case ResolveErrorKind.unavailable:
      return 'This video is private, removed, or needs a sign-in to watch.';
    case ResolveErrorKind.network:
      return "Couldn't reach the site. Check your connection and try again.";
    case ResolveErrorKind.timeout:
      return 'Finding the video took too long. Try again in a moment.';
    case ResolveErrorKind.unknown:
      return "Couldn't find a playable video behind that link. Check the "
          'link and try again.';
  }
}
