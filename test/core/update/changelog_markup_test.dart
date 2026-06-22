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
      expect(p.chips, const [
        ChangelogChip(ChangelogTag.added),
        ChangelogChip(ChangelogTag.fixed),
      ]);
      expect(p.highlights, hasLength(3));
      expect(spansToPlainText(p.highlights.first), 'first thing (#136)');
      expect(p.sections, hasLength(2));
      expect(p.sections.first.tag, ChangelogTag.added);
    });

    test('explicit > summary wins over derivation and sets hasHeadline', () {
      final p = parseChangelogNotes('> The headline.\n\n### Added\n- something');
      expect(p.summary, 'The headline.');
      expect(p.hasHeadline, isTrue);
    });

    test('derived summary = first sentence of first bullet, refs stripped', () {
      final p = parseChangelogNotes('- Keeps the latest video per room. More text. (#136)');
      expect(p.summary, 'Keeps the latest video per room.');
      expect(p.hasHeadline, isFalse); // derived, not an authored headline
    });

    test('flat paragraph entry (no headings) still parses', () {
      final p = parseChangelogNotes('Fixed a freeze that could happen on resume.');
      expect(p.chips, isEmpty);
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

    test('a wrapped bullet folds indented continuation lines into one item', () {
      // Mirrors the real 0.32.0 entry: a bullet wrapping over several physical
      // lines with a 2-space hanging indent. Must stay ONE bullet, not split
      // into a truncated bullet + a stray paragraph.
      final p = parseChangelogNotes('''
### Added
- Continue watching now keeps only the latest video per room by default, with a
  Settings toggle in both the lobby and the in-room gear. (#136)
- Second bullet.
''');
      expect(p.highlights, hasLength(2));
      expect(
        spansToPlainText(p.highlights.first),
        'Continue watching now keeps only the latest video per room by default, '
        'with a Settings toggle in both the lobby and the in-room gear. (#136)',
      );
      // No paragraph block leaked from the continuation.
      final blocks = p.sections.single.blocks;
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<BulletList>());
      // Summary reaches into the continuation (the bug truncated it at the first
      // physical line, ending "…with a" with no "Settings").
      expect(p.summary, contains('Settings'));
      expect(p.summary.endsWith('with a'), isFalse);
    });

    test('empty and whitespace input never throw', () {
      expect(parseChangelogNotes('').sections, isEmpty);
      expect(parseChangelogNotes('   \n\n  ').sections, isEmpty);
      expect(parseChangelogNotes('').summary, '');
    });

    test('an overflowing issue-ref digit run never throws and degrades', () {
      const huge = '#99999999999999999999'; // > 64-bit, cannot int.parse
      expect(() => parseChangelogNotes('- fixed $huge'), returnsNormally);
      final spans = parseInline('see $huge done');
      // Falls back to literal text — no IssueRef, original chars preserved.
      expect(spans.whereType<IssueRef>(), isEmpty);
      expect(spansToPlainText(spans), 'see $huge done');
    });
  });

  group('descriptive chip labels', () {
    test('a bare ### heading yields a chip with no custom label', () {
      final p = parseChangelogNotes('### Fixed\n- a bug');
      expect(p.chips, const [ChangelogChip(ChangelogTag.fixed)]);
      expect(p.chips.single.label, isNull);
      expect(p.chips.single.text, 'Fixed'); // falls back to the category word
      expect(p.sections.single.chipLabel, isNull);
    });

    test('### Improved: <label> keeps the category but adds a custom label', () {
      final p = parseChangelogNotes('### Improved: Better changelog\n- prettier');
      expect(p.chips, const [
        ChangelogChip(ChangelogTag.improved, 'Better changelog'),
      ]);
      expect(p.chips.single.text, 'Better changelog');
      expect(p.sections.single.tag, ChangelogTag.improved);
      expect(p.sections.single.chipLabel, 'Better changelog');
    });

    test('a non-category heading produces no chip but keeps its title', () {
      final p = parseChangelogNotes('### Notes\n- something');
      expect(p.chips, isEmpty);
      expect(p.sections.single.tag, isNull);
      expect(p.sections.single.title, 'Notes');
    });

    test('repeated bare headings dedupe; distinct labels each keep a chip', () {
      final p = parseChangelogNotes(
        '### Fixed\n- a\n\n### Fixed\n- b\n\n### Fixed: edge case\n- c',
      );
      expect(p.chips, const [
        ChangelogChip(ChangelogTag.fixed),
        ChangelogChip(ChangelogTag.fixed, 'edge case'),
      ]);
    });
  });

  group('inferChipsFromVersion', () {
    test('a patch release (non-zero 3rd digit) infers Fixed', () {
      expect(inferChipsFromVersion('0.31.2-alpha'),
          const [ChangelogChip(ChangelogTag.fixed)]);
      expect(inferChipsFromVersion('1.4.7'),
          const [ChangelogChip(ChangelogTag.fixed)]);
    });

    test('a minor or major release (zero 3rd digit) infers New', () {
      expect(inferChipsFromVersion('0.32.0-alpha'),
          const [ChangelogChip(ChangelogTag.added)]);
      expect(inferChipsFromVersion('1.0.0'),
          const [ChangelogChip(ChangelogTag.added)]);
    });

    test('a two-part version (no patch) infers New', () {
      expect(inferChipsFromVersion('0.32'),
          const [ChangelogChip(ChangelogTag.added)]);
    });

    test('an unparseable version yields no chip (never throws)', () {
      expect(inferChipsFromVersion('nightly'), isEmpty);
      expect(inferChipsFromVersion(''), isEmpty);
      expect(() => inferChipsFromVersion('???'), returnsNormally);
    });
  });
}
