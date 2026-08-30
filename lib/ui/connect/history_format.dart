import '../../core/data/history_entry.dart';

/// Formatting helpers for the "Continue watching" list. Pure functions so the
/// wording/edge cases can be unit-tested without pumping a widget.

/// `m:ss` under an hour, `h:mm:ss` at or above one hour.
String formatRuntime(int milliseconds) {
  final d = Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
  String two(int n) => n.toString().padLeft(2, '0');
  final seconds = d.inSeconds % 60;
  if (d.inHours > 0) {
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(seconds)}';
  }
  return '${d.inMinutes}:${two(seconds)}';
}

/// Coarse "x ago" label for when a file was last played.
String relativeTime(DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  final days = diff.inDays;
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  if (days < 30) {
    final weeks = days ~/ 7;
    return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
  }
  final months = days ~/ 30;
  return months <= 1 ? '1 month ago' : '$months months ago';
}

/// Progress fraction [0,1], or null when the duration is unknown.
double? progressFraction(HistoryEntry e) {
  final dur = e.durationMs;
  if (dur == null || dur <= 0) return null;
  return (e.lastPositionMs / dur).clamp(0.0, 1.0);
}

/// Human file size (`1.4 GB`, `720 MB`, `512 KB`), or `''` when unknown (0).
String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  const unit = 1024.0;
  final mb = bytes / (unit * unit);
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
  if (mb >= 1) return '${mb.toStringAsFixed(0)} MB';
  return '${(bytes / unit).toStringAsFixed(0)} KB';
}

/// Second card line: where it was watched. Local rows say `Local`.
/// Synced rows say `in <room>` or `in <room> as <name>`.
String? historyRoomLine(HistoryEntry e) {
  if (e.isLocalContext) return 'Local';
  final room = e.room;
  if (room == null || room.isEmpty) return 'Local';
  final name = e.username;
  if (name == null || name.isEmpty) return 'in $room';
  return 'in $room as $name';
}

/// One-line summary: resume position, total runtime, percent, last-played, and
/// file size when known. Falls back to last-played (+ size) when duration is
/// unknown.
String historySubtitle(HistoryEntry e, DateTime now) {
  final played = relativeTime(e.playedAt, now);
  final size = formatFileSize(e.fileSizeBytes);
  final tail = size.isEmpty ? played : '$played · $size';
  final frac = progressFraction(e);
  if (frac == null) return tail;
  final pct = (frac * 100).round();
  return '${formatRuntime(e.lastPositionMs)} / ${formatRuntime(e.durationMs!)} · $pct% · $tail';
}
