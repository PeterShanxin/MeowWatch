import 'dart:convert' show LineSplitter;

import 'update_service.dart' show ChangelogEntry;

/// Matches a version header line: `## [0.33.0-alpha] - 2026-06-21`.
final RegExp _entryHeader = RegExp(r'^##\s+\[([^\]]+)\]\s*-\s*(.+?)\s*$');

/// Parse a full `CHANGELOG.md` into per-version [ChangelogEntry]s, newest first.
///
/// Splits on `## [version] - date` headers; the lines between one header and the
/// next are that version's `notes`. Any intro text before the first header (the
/// file's preamble / writing-style pointer) is ignored. Total — never throws on
/// any input; malformed/empty markdown yields a best-effort (possibly empty)
/// list so the caller can simply skip the modal.
List<ChangelogEntry> parseChangelogFile(String markdown) {
  final lines = const LineSplitter().convert(markdown);
  final entries = <ChangelogEntry>[];

  String? version;
  String? date;
  var body = <String>[];

  void flush() {
    if (version != null) {
      entries.add(ChangelogEntry(
        version: version,
        date: date ?? '',
        notes: body.join('\n').trim(),
      ));
    }
  }

  for (final line in lines) {
    final m = _entryHeader.firstMatch(line);
    if (m != null) {
      flush();
      version = m.group(1)!.trim();
      date = m.group(2)!.trim();
      body = <String>[];
    } else if (version != null) {
      body.add(line);
    }
  }
  flush();
  return entries;
}

/// The entry whose version equals [version] (trimmed), or null if none match.
ChangelogEntry? entryForVersion(
  List<ChangelogEntry> entries,
  String version,
) {
  final want = version.trim();
  for (final e in entries) {
    if (e.version.trim() == want) return e;
  }
  return null;
}
