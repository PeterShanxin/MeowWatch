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
    this.audioHeaders = const {},
    this.title,
  });

  /// The original page URL the user pasted — announced to the room.
  final String pageUrl;

  /// Stream URL handed to the player.
  final String videoUrl;

  /// Second stream when yt-dlp returned split video+audio formats.
  final String? audioUrl;

  /// Headers required by the video CDN (e.g. Bilibili needs Referer or it 403s).
  final Map<String, String> httpHeaders;

  /// Headers for the separate [audioUrl] stream. Split CDNs gate the audio
  /// request on the same Referer as the video, so these must be applied when
  /// the external audio track is added — falls back to [httpHeaders] when the
  /// audio format did not carry its own. Empty when the media is muxed.
  final Map<String, String> audioHeaders;

  /// Video title when the extractor provided one.
  final String? title;
}
