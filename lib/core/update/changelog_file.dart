import 'dart:convert' show LineSplitter;

import 'semver.dart';
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

/// The entries to show in the post-update catch-up modal: every version newer
/// than [lastSeen] up to and including [current], in the file's newest-first
/// order. So a user 10 versions behind sees all 10 (newest as the hero, the
/// rest in the collapsible "Earlier updates").
///
/// Falls back to just the [current] entry when [lastSeen] is null/blank or no
/// entry is strictly newer than it (e.g. the `MEOWWATCH_WHATS_NEW` backdoor on
/// a fresh install, where there is no real "since"). Entries newer than
/// [current] (should not occur — [current] is the file's top) are excluded so
/// the modal never previews a version the user does not have. Returns an empty
/// list only when even [current] is absent. Total — never throws.
List<ChangelogEntry> entriesForWhatsNew(
  List<ChangelogEntry> entries, {
  required String? lastSeen,
  required String current,
}) {
  final prev = lastSeen?.trim();
  if (prev != null && prev.isNotEmpty) {
    final span = entries
        .where((e) =>
            isVersionNewer(e.version, prev) &&
            !isVersionNewer(e.version, current))
        .toList();
    if (span.isNotEmpty) return span;
  }
  final cur = entryForVersion(entries, current);
  return cur != null ? [cur] : const <ChangelogEntry>[];
}
