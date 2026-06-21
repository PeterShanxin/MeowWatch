// test/core/update/changelog_markup_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/changelog_markup.dart';

void main() {
  group('parseInline', () {
    test('plain text → one PlainText span', () {
      final spans = parseInline('just words');
      expect(spans, hasLength(1));
      expect(spans.single, isA<PlainText>());
      expect((spans.single as PlainText).text, 'just words');
    });

    test('bold, code, and issue ref are extracted with plain text between', () {
      final spans = parseInline('see **this** and `that` plus #136 done');
      expect(spans.map((s) => s.runtimeType).toList(), [
        PlainText, BoldText, PlainText, CodeText, PlainText, IssueRef, PlainText,
      ]);
      expect((spans[1] as BoldText).text, 'this');
      expect((spans[3] as CodeText).text, 'that');
      expect((spans[5] as IssueRef).number, 136);
    });

    test('issue ref inside parens keeps the parens as plain text', () {
      final spans = parseInline('fixed it (#147)');
      expect((spans[0] as PlainText).text, 'fixed it (');
      expect((spans[1] as IssueRef).number, 147);
      expect((spans[2] as PlainText).text, ')');
    });

    test('spansToPlainText flattens, rendering an issue ref as #n', () {
      expect(spansToPlainText(parseInline('a **b** `c` #9')), 'a b c #9');
    });

    test('ChangelogTag.label maps to user-facing words', () {
      expect(ChangelogTag.added.label, 'New');
      expect(ChangelogTag.fixed.label, 'Fixed');
      expect(ChangelogTag.improved.label, 'Improved');
    });
  });

  group('parseChangelogNotes', () {
    test('sectioned entry yields tags, highlights, and sections', () {
      final p = parseChangelogNotes('''
### Added
- first **thing** (#136)
- second thing

### Fixed
- a bug
''');
      expect(p.tags, [ChangelogTag.added, ChangelogTag.fixed]);
      expect(p.highlights, hasLength(3));
      expect(spansToPlainText(p.highlights.first), 'first thing (#136)');
      expect(p.sections, hasLength(2));
      expect(p.sections.first.tag, ChangelogTag.added);
    });

    test('explicit > summary wins over derivation', () {
      final p = parseChangelogNotes('> The headline.\n\n### Added\n- something');
      expect(p.summary, 'The headline.');
    });

    test('derived summary = first sentence of first bullet, refs stripped', () {
      final p = parseChangelogNotes('- Keeps the latest video per room. More text. (#136)');
      expect(p.summary, 'Keeps the latest video per room.');
    });

    test('flat paragraph entry (no headings) still parses', () {
      final p = parseChangelogNotes('Fixed a freeze that could happen on resume.');
      expect(p.tags, isEmpty);
      expect(p.highlights, isEmpty);
      expect(p.summary, 'Fixed a freeze that could happen on resume.');
      expect(p.sections, hasLength(1));
      expect(p.sections.single.blocks.single, isA<Paragraph>());
    });

    test('long summary is truncated with an ellipsis', () {
      final p = parseChangelogNotes('- ${'x' * 200}');
      expect(p.summary.length, lessThanOrEqualTo(91));
      expect(p.summary.endsWith('…'), isTrue);
    });

    test('empty and whitespace input never throw', () {
      expect(parseChangelogNotes('').sections, isEmpty);
      expect(parseChangelogNotes('   \n\n  ').sections, isEmpty);
      expect(parseChangelogNotes('').summary, '');
    });
  });
}
