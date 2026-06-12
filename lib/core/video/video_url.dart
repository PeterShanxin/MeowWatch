import 'package:path/path.dart' as p;

/// Pure helpers for treating a media *source* string as either a local file
/// path or a direct `http(s)` stream URL. mpv (via media_kit) plays both from
/// the same `Media(source)` slot, so the only real work is UI-side: validating
/// pasted links and deciding what name to show / announce to the room.

/// Whether [source] looks like an `http(s)` URL we can hand straight to mpv.
///
/// Requires a parseable URI with an `http`/`https` scheme and a non-empty host
/// — so `http://` alone (no host) or a bare Windows path like `C:\video.mp4`
/// (whose "scheme" would parse as `c`) are both rejected.
bool isHttpUrl(String source) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null) return false;
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

/// Validate a pasted link before we try to load it. Returns `null` when [input]
/// is a usable URL, otherwise a short, user-facing reason. Kept separate from
/// the widget so the rules are unit-testable headless.
String? videoUrlError(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return 'Paste a video link first';
  if (!isHttpUrl(trimmed)) {
    return "That doesn't look like a link — it should start with http:// or https://";
  }
  return null;
}

/// The name to display for and announce to the room for [source].
///
/// For a URL we send the whole link as the name — this matches official
/// Syncplay (a stream has no byte size, so the URL is the only stable
/// identity, and two peers pasting the same link then read as the same media).
/// For a local file we keep just the base filename, as before.
String mediaSourceName(String source) =>
    isHttpUrl(source) ? source.trim() : p.basename(source);

/// Turn a raw mpv/playback error (or its absence) into a friendly explanation
/// for a failed load. mpv's own messages are terse and inconsistent, so we lead
/// with the most common real causes for a pasted link and keep the wording the
/// same for a local file that won't open.
String friendlyPlaybackError({required bool isUrl}) {
  if (isUrl) {
    return "Couldn't play that link. It might be unreachable, not a direct "
        'video, or expired. Check the link and try again.';
  }
  return "Couldn't play that video. The file may be missing, moved, or in a "
      'format this player cannot read.';
}
