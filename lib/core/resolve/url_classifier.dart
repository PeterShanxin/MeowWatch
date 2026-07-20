import 'package:meowwatch/core/video/video_url.dart';

/// Decides whether a pasted `http(s)` URL is a *page* that needs yt-dlp to
/// dig out the real stream, or a direct media file mpv can play as-is.
/// Pure and headless so the rules are unit-testable.

/// File extensions mpv handles directly — a URL ending in one of these
/// (query string stripped first) skips the resolver entirely.
const Set<String> _kDirectMediaExtensions = {
  '.mp4', '.mkv', '.webm', '.m3u8', '.ts', '.mov', '.avi', // video
  '.mp3', '.m4a', '.aac', '.flac', '.ogg', '.opus', '.wav', // audio
};

/// True when [url] is an `http(s)` page URL that needs yt-dlp resolution
/// (i.e. it is a valid web link but does not point at a direct media file).
/// Non-http sources (local paths, other schemes) never need the resolver.
bool needsResolver(String url) {
  if (!isHttpUrl(url)) return false;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  final path = uri.path; // query string already excluded from `path`
  final dot = path.lastIndexOf('.');
  if (dot < 0) return true;
  final extension = path.substring(dot).toLowerCase();
  return !_kDirectMediaExtensions.contains(extension);
}
