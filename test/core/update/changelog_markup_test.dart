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
}
