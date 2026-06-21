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
      spans.add(IssueRef(int.parse(m.group(3)!)));
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
  const NoteSection({this.tag, this.title, required this.blocks});
  final ChangelogTag? tag;
  final String? title;
  final List<NoteBlock> blocks;
}

/// The fully parsed entry.
class ParsedNotes {
  const ParsedNotes({
    required this.summary,
    required this.tags,
    required this.highlights,
    required this.sections,
  });
  final String summary;
  final List<ChangelogTag> tags;
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
final RegExp _issueStrip = RegExp(r'\s*\(?#\d+\)?');
final RegExp _sentenceEnd = RegExp(r'[.!?](\s|$)');

/// Parse one entry's raw markdown `notes` into a render-ready [ParsedNotes].
/// Total: never throws.
ParsedNotes parseChangelogNotes(String notes) {
  final lines = const LineSplitter().convert(notes);
  String? summaryOverride;
  final sections = <NoteSection>[];

  ChangelogTag? curTag;
  String? curTitle;
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
      sections.add(NoteSection(tag: curTag, title: curTitle, blocks: curBlocks));
    }
    curTag = null;
    curTitle = null;
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
      curTag = _tagByHeading[curTitle!.toLowerCase()];
      continue;
    }
    final b = _bullet.firstMatch(trimmed);
    if (b != null) {
      flushPara();
      (bullets ??= <String>[]).add(b.group(1)!.trim());
      continue;
    }
    flushBullets();
    para.add(trimmed);
  }
  flushSection();

  final tags = <ChangelogTag>[];
  for (final t in const [
    ChangelogTag.added,
    ChangelogTag.fixed,
    ChangelogTag.improved,
  ]) {
    if (sections.any((s) => s.tag == t)) tags.add(t);
  }

  final highlights = <List<NoteSpan>>[];
  for (final s in sections) {
    for (final blk in s.blocks) {
      if (blk is BulletList) highlights.addAll(blk.items);
    }
  }

  final summary = (summaryOverride != null && summaryOverride.isNotEmpty)
      ? summaryOverride
      : _deriveSummary(sections, highlights);

  return ParsedNotes(
    summary: summary,
    tags: tags,
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
  source = source.replaceAll(_issueStrip, '').trim();
  final m = _sentenceEnd.firstMatch(source);
  var summary = m != null ? source.substring(0, m.start + 1) : source;
  if (summary.length > 90) summary = '${summary.substring(0, 89).trim()}…';
  return summary;
}
