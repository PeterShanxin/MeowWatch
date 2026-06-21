// lib/core/update/changelog_markup.dart
//
// Pure, dependency-free parser turning a changelog entry's raw markdown `notes`
// into a render-ready model. It is TOTAL — it never throws on any input — so the
// updater dialog can always render something. Handles only the fixed subset we
// author in CHANGELOG.md: **bold**, `code`, #issue refs, ### headings, bullets,
// blank-line paragraphs, and an optional leading `> summary` line.

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
