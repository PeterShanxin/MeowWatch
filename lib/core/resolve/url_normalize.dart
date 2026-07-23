/// Canonicalize a pasted page URL before it is resolved and shared to the room
/// (#228 follow-up). Two goals:
///
/// 1. **Dedup.** `youtu.be/ID?si=A`, `youtu.be/ID?si=B`, and
///    `youtube.com/watch?v=ID&t=17s` are the same video; collapsing them to one
///    canonical string means both co-watchers announce an identical link and the
///    room can't split over a tracking token.
/// 2. **Cleanliness.** Share tokens (`si`), analytics params, and per-viewer
///    start times are noise the resolver and the room don't need.
///
/// Only applied to page URLs that go through the resolver — never to a direct
/// stream URL, whose signed query string is load-bearing.
library;

/// Query keys that are pure tracking/analytics and safe to drop from any site.
/// Deliberately a small denylist so meaningful params (e.g. Bilibili `p=` for
/// the sub-video) are preserved.
const _trackingParams = {
  'si', // YouTube/Bilibili share token
  'feature',
  'pp',
  'spm_id_from', // Bilibili
  'vd_source', // Bilibili
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'fbclid',
  'gclid',
};

/// YouTube hosts we canonicalize to a bare `youtu.be/<id>`.
const _youTubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
};

/// Return the canonical form of [raw]. Non-URLs and unparseable strings are
/// returned trimmed-but-otherwise-unchanged so a local file path or a typo is
/// never mangled.
String normalizePageUrl(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || !uri.isScheme('https') && !uri.isScheme('http')) {
    return trimmed;
  }

  final host = uri.host.toLowerCase();
  if (_youTubeHosts.contains(host)) {
    final id = _youTubeId(uri);
    if (id != null) return 'https://youtu.be/$id';
    // A YouTube URL we don't recognize the shape of (channel, playlist page):
    // fall through to generic tracking-strip rather than guessing an id.
  }

  return _stripTracking(uri);
}

/// Extract the 11-char video id from any recognized YouTube URL shape, or null.
String? _youTubeId(Uri uri) {
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments;

  // youtu.be/<id>
  if (host == 'youtu.be' && segments.isNotEmpty) {
    return _validId(segments.first);
  }
  // youtube.com/watch?v=<id>
  final v = uri.queryParameters['v'];
  if (v != null) return _validId(v);
  // youtube.com/shorts/<id>, /embed/<id>, /live/<id>, /v/<id>
  if (segments.length >= 2 &&
      const {'shorts', 'embed', 'live', 'v'}.contains(segments.first)) {
    return _validId(segments[1]);
  }
  return null;
}

/// A YouTube id is exactly 11 URL-safe base64 chars. Guard so a stray path
/// segment isn't treated as an id.
String? _validId(String candidate) {
  return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(candidate) ? candidate : null;
}

/// Rebuild [uri] with only the tracking params removed, order preserved.
String _stripTracking(Uri uri) {
  if (uri.queryParameters.isEmpty) return uri.toString();
  final kept = <String, String>{
    for (final entry in uri.queryParameters.entries)
      if (!_trackingParams.contains(entry.key.toLowerCase()))
        entry.key: entry.value,
  };
  if (kept.length == uri.queryParameters.length) return uri.toString();
  return uri.replace(queryParameters: kept.isEmpty ? null : kept).toString();
}
