/// Result of resolving a page URL (YouTube, Bilibili, …) into playable
/// stream URLs via yt-dlp. Immutable.
///
/// [pageUrl] is what the room shares (stable for every peer); the stream
/// URLs are signed/short-lived/IP-bound and must never leave this machine.
class ResolvedMedia {
  const ResolvedMedia({
    required this.pageUrl,
    required this.videoUrl,
    this.audioUrl,
    this.httpHeaders = const {},
    this.title,
  });

  /// The original page URL the user pasted — announced to the room.
  final String pageUrl;

  /// Stream URL handed to the player.
  final String videoUrl;

  /// Second stream when yt-dlp returned split video+audio formats.
  final String? audioUrl;

  /// Headers required by the CDN (e.g. Bilibili needs Referer or it 403s).
  final Map<String, String> httpHeaders;

  /// Video title when the extractor provided one.
  final String? title;
}
