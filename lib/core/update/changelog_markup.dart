// lib/core/update/changelog_markup.dart
//
// Pure, dependency-free parser turning a changelog entry's raw markdown `notes`
// into a render-ready model. It is TOTAL — it never throws on any input — so the
// updater dialog can always render something. Handles only the fixed subset we
// author in CHANGELOG.md: **bold**, `code`, #issue refs, ### headings, bullets,
// blank-line paragraphs, and an optional leading `> summary` line.

import 'dart:convert' show LineSplitter;

/// A category derived from a `### Added/Fixed/Changed/Improved` heading.
enum ChangelogTag { added, fixed, improved }

extension ChangelogTagLabel on ChangelogTag {
  /// User-facing chip label.
  String get label => switch (this) {
        ChangelogTag.added => 'New',
        ChangelogTag.fixed => 'Fixed',
        ChangelogTag.improved => 'Improved',
      };
}

/// A category chip to display: [tag] drives the color + icon, optional [label]
/// is short custom text. Authored as `### Improved: Better release notes` — the
/// word before the colon picks the category, the rest becomes the label. With
/// no custom label the chip falls back to the category word ([text]).
class ChangelogChip {
  const ChangelogChip(this.tag, [this.label]);
  final ChangelogTag tag;
  final String? label;

  /// Rendered text: the custom label when present, else the category word.
  String get text => label ?? tag.label;

  @override
  bool operator ==(Object other) =>
      other is ChangelogChip && other.tag == tag && other.label == label;

  @override
  int get hashCode => Object.hash(tag, label);
}

/// One inline run of formatted text.
sealed class NoteSpan {
  const NoteSpan();
}

class PlainText extends NoteSpan {
  const PlainText(this.text);
  final String text;
}

class BoldText extends NoteSpan {
  const BoldText(this.text);
  final String text;
}

class CodeText extends NoteSpan {
  const CodeText(this.text);
  final String text;
}

class IssueRef extends NoteSpan {
  const IssueRef(this.number);
  final int number;
}

final RegExp _inlineToken = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|#(\d+)');

/// Split [text] into inline spans. Anything outside a recognized token stays
/// PlainText, so the result always reproduces the original characters.
List<NoteSpan> parseInline(String text) {
  final spans = <NoteSpan>[];
  var index = 0;
  for (final m in _inlineToken.allMatches(text)) {
    if (m.start > index) spans.add(PlainText(text.substring(index, m.start)));
    if (m.group(1) != null) {
      spans.add(BoldText(m.group(1)!));
    } else if (m.group(2) != null) {
      spans.add(CodeText(m.group(2)!));
    } else {
      // tryParse, not parse: a digit run that overflows a 64-bit int must not
      // throw (the parser is total). Fall back to the literal text so the
      // original characters are still reproduced.
      final n = int.tryParse(m.group(3)!);
      if (n != null) {
        spans.add(IssueRef(n));
      } else {
        spans.add(PlainText(m.group(0)!));
      }
    }
    index = m.end;
  }
  if (index < text.length) spans.add(PlainText(text.substring(index)));
  if (spans.isEmpty) spans.add(const PlainText(''));
  return spans;
}

/// Flatten spans back to a plain string (issue refs render as `#n`).
String spansToPlainText(List<NoteSpan> spans) {
  final b = StringBuffer();
  for (final s in spans) {
    switch (s) {
      case PlainText(:final text):
        b.write(text);
      case BoldText(:final text):
        b.write(text);
      case CodeText(:final text):
        b.write(text);
      case IssueRef(:final number):
        b.write('#$number');
    }
  }
  return b.toString();
}

/// A block within a section.
sealed class NoteBlock {
  const NoteBlock();
}

class Paragraph extends NoteBlock {
  const Paragraph(this.spans);
  final List<NoteSpan> spans;
}

class BulletList extends NoteBlock {
  const BulletList(this.items);
  final List<List<NoteSpan>> items;
}

/// A section, optionally introduced by a `### Heading`.
class NoteSection {
  const NoteSection({
    this.tag,
    this.title,
    this.chipLabel,
    required this.blocks,
  });
  final ChangelogTag? tag;
  final String? title;

  /// Short custom chip label from a `### Improved: <label>` heading; null when
  /// the heading is a bare `### Improved` (the chip then shows the tag word).
  final String? chipLabel;
  final List<NoteBlock> blocks;
}

/// The fully parsed entry.
class ParsedNotes {
  const ParsedNotes({
    required this.summary,
    required this.hasHeadline,
    required this.chips,
    required this.highlights,
    required this.sections,
  });
  final String summary;

  /// True when [summary] came from an explicit leading `> summary` line (the
  /// authored headline) rather than being derived from the first bullet. The
  /// hero shows an explicit headline above the highlights; a derived summary is
  /// not rendered separately (it would just repeat the first bullet).
  final bool hasHeadline;

  /// Category chips for this entry, in document order (deduplicated). Empty when
  /// the entry has no `### Added/Fixed/Improved` sections — the view then infers
  /// one from the version via [inferChipsFromVersion].
  final List<ChangelogChip> chips;
  final List<List<NoteSpan>> highlights;
  final List<NoteSection> sections;
}

const Map<String, ChangelogTag> _tagByHeading = {
  'added': ChangelogTag.added,
  'fixed': ChangelogTag.fixed,
  'changed': ChangelogTag.improved,
  'improved': ChangelogTag.improved,
};

final RegExp _heading = RegExp(r'^###\s+(.+)$');
final RegExp _bullet = RegExp(r'^[-*]\s+(.+)$');
final RegExp _leadingSpace = RegExp(r'^[ \t]');
final RegExp _issueStrip = RegExp(r'\s*\(?#\d+\)?');
final RegExp _sentenceEnd = RegExp(r'[.!?](\s|$)');
final RegExp _verSplit = RegExp(r'[-+]');

/// Split a `### Heading` into its category tag and optional custom chip label.
/// `Fixed` → (fixed, null); `Improved: Better notes` → (improved, 'Better
/// notes'); a non-category heading like `Notes` → (null, null).
(ChangelogTag?, String?) _parseHeading(String heading) {
  final sep = heading.indexOf(':');
  final word = (sep >= 0 ? heading.substring(0, sep) : heading).trim();
  final tag = _tagByHeading[word.toLowerCase()];
  if (tag == null) return (null, null);
  final rest = sep >= 0 ? heading.substring(sep + 1).trim() : '';
  return (tag, rest.isEmpty ? null : rest);
}

/// When an entry has no authored category sections, infer one chip from its
/// version number: a patch release (non-zero 3rd digit, e.g. `0.31.2`) is a
/// fix; a minor or major release (`0.32.0`, `1.0.0`) is new. Returns empty for
/// a version with no parseable `major.minor`. Total — never throws.
List<ChangelogChip> inferChipsFromVersion(String version) {
  final parts = version.split(_verSplit).first.split('.');
  if (parts.length < 2 ||
      int.tryParse(parts[0]) == null ||
      int.tryParse(parts[1]) == null) {
    return const [];
  }
  final patch = parts.length >= 3 ? int.tryParse(parts[2]) : 0;
  return (patch != null && patch > 0)
      ? const [ChangelogChip(ChangelogTag.fixed)]
      : const [ChangelogChip(ChangelogTag.added)];
}

/// Category chips to show for one version: its authored chips, or — when it
/// has none (a free-form entry with no `### Added/Fixed/Improved` sections) —
/// one inferred from [version]. Shared by the single-version hero/row display
/// and by [combineChips] for the multi-version catch-up hero.
List<ChangelogChip> chipsForVersion(String version, ParsedNotes parsed) =>
    parsed.chips.isNotEmpty ? parsed.chips : inferChipsFromVersion(version);

/// Category chips gathered across every included version, in the given
/// (newest-first) order, deduplicated by (tag, label) — the same rule
/// [parseChangelogNotes] applies within one entry. Powers the multi-version
/// catch-up hero's combined chip wrap, so a custom-labeled chip from an older
/// version still earns its own pill instead of collapsing into the bare
/// category word. [versions] and [parsed] must be the same length, index-
/// aligned. Total; empty input yields no chips.
List<ChangelogChip> combineChips(
  List<String> versions,
  List<ParsedNotes> parsed,
) {
  final chips = <ChangelogChip>[];
  final seen = <ChangelogChip>{};
  for (var i = 0; i < parsed.length; i++) {
    for (final c in chipsForVersion(versions[i], parsed[i])) {
      if (seen.add(c)) chips.add(c);
    }
  }
  return chips;
}

/// Up to [max] highlights summarizing every included version's [parsed]
/// (newest-first) bullets: round-robin across each version's bullet list so a
/// multi-version catch-up shows one bullet from several versions rather than
/// several bullets from just the newest — "here's everything you just got",
/// not a re-run of the newest version's own highlights. Total; returns fewer
/// than [max] when there simply aren't that many bullets across every
/// included version (never pads with anything else).
List<List<NoteSpan>> combinedHighlights(
  List<ParsedNotes> parsed, {
  int max = 4,
}) {
  final combined = <List<NoteSpan>>[];
  var round = 0;
  while (combined.length < max) {
    var addedAny = false;
    for (final p in parsed) {
      if (round < p.highlights.length) {
        combined.add(p.highlights[round]);
        addedAny = true;
        if (combined.length >= max) break;
      }
    }
    if (!addedAny) break;
    round++;
  }
  return combined;
}

/// Parse one entry's raw markdown `notes` into a render-ready [ParsedNotes].
/// Total: never throws.
ParsedNotes parseChangelogNotes(String notes) {
  final lines = const LineSplitter().convert(notes);
  String? summaryOverride;
  final sections = <NoteSection>[];

  ChangelogTag? curTag;
  String? curTitle;
  String? curChipLabel;
  var curBlocks = <NoteBlock>[];
  var para = <String>[];
  List<String>? bullets;

  void flushPara() {
    if (para.isNotEmpty) {
      curBlocks.add(Paragraph(parseInline(para.join(' '))));
      para = <String>[];
    }
  }

  void flushBullets() {
    if (bullets != null && bullets!.isNotEmpty) {
      curBlocks.add(BulletList(bullets!.map(parseInline).toList()));
    }
    bullets = null;
  }

  void flushSection() {
    flushBullets();
    flushPara();
    if (curTag != null || curTitle != null || curBlocks.isNotEmpty) {
      sections.add(NoteSection(
        tag: curTag,
        title: curTitle,
        chipLabel: curChipLabel,
        blocks: curBlocks,
      ));
    }
    curTag = null;
    curTitle = null;
    curChipLabel = null;
    curBlocks = <NoteBlock>[];
  }

  for (final raw in lines) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      flushBullets();
      flushPara();
      continue;
    }
    if (trimmed.startsWith('>')) {
      summaryOverride ??= trimmed.replaceFirst(RegExp(r'^>\s?'), '').trim();
      continue;
    }
    final h = _heading.firstMatch(trimmed);
    if (h != null) {
      flushSection();
      curTitle = h.group(1)!.trim();
      final (tag, chipLabel) = _parseHeading(curTitle!);
      curTag = tag;
      curChipLabel = chipLabel;
      continue;
    }
    final b = _bullet.firstMatch(trimmed);
    if (b != null) {
      flushPara();
      (bullets ??= <String>[]).add(b.group(1)!.trim());
      continue;
    }
    // An indented, non-bullet line while a bullet list is open is a wrapped
    // continuation of the last bullet — CHANGELOG bullets wrap at ~80 cols with
    // a 2-space hanging indent (e.g. the 0.32.0 entry). Fold it back into that
    // item instead of flushing the list and starting a paragraph, which would
    // truncate the derived summary to the first physical line and split the
    // continuation out of the full notes.
    if (bullets != null && bullets!.isNotEmpty && _leadingSpace.hasMatch(raw)) {
      bullets![bullets!.length - 1] = '${bullets!.last} $trimmed';
      continue;
    }
    flushBullets();
    para.add(trimmed);
  }
  flushSection();

  // Chips in document order (matching reading order), deduplicated by
  // (tag, label) so a repeated bare `### Fixed` collapses to one chip while two
  // distinctly-labeled sections each keep theirs.
  final chips = <ChangelogChip>[];
  final seenChips = <ChangelogChip>{};
  for (final s in sections) {
    if (s.tag == null) continue;
    final chip = ChangelogChip(s.tag!, s.chipLabel);
    if (seenChips.add(chip)) chips.add(chip);
  }

  final highlights = <List<NoteSpan>>[];
  for (final s in sections) {
    for (final blk in s.blocks) {
      if (blk is BulletList) highlights.addAll(blk.items);
    }
  }

  final hasHeadline = summaryOverride != null && summaryOverride.isNotEmpty;
  final summary =
      hasHeadline ? summaryOverride : _deriveSummary(sections, highlights);

  return ParsedNotes(
    summary: summary,
    hasHeadline: hasHeadline,
    chips: chips,
    highlights: highlights,
    sections: sections,
  );
}

String _deriveSummary(
  List<NoteSection> sections,
  List<List<NoteSpan>> highlights,
) {
  var source = '';
  if (highlights.isNotEmpty) {
    source = spansToPlainText(highlights.first);
  } else {
    outer:
    for (final s in sections) {
      for (final blk in s.blocks) {
        if (blk is Paragraph) {
          source = spansToPlainText(blk.spans);
          break outer;
        }
      }
    }
  }
  source = source
      .replaceAll(_issueStrip, '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  final m = _sentenceEnd.firstMatch(source);
  var summary = m != null ? source.substring(0, m.start + 1) : source;
  if (summary.length > 90) summary = '${summary.substring(0, 89).trim()}…';
  return summary;
}
