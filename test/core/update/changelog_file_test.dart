import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/changelog_file.dart';

void main() {
  const sample = '''
# Changelog

Intro paragraph that must be ignored.

> Writing style pointer, also ignored.

## [0.33.0-alpha] - 2026-06-21
> The headline.

### Added
- A shiny thing (#136)

## [0.32.0-alpha] - 2026-06-20

### Added
- An older thing
''';

  group('parseChangelogFile', () {
    test('splits into per-version entries, newest first, intro ignored', () {
      final entries = parseChangelogFile(sample);
      expect(entries.map((e) => e.version), ['0.33.0-alpha', '0.32.0-alpha']);
      expect(entries.first.date, '2026-06-21');
      expect(entries.first.notes, contains('A shiny thing (#136)'));
      expect(entries.first.notes, contains('> The headline.'));
      // Intro text is not part of any entry.
      expect(entries.first.notes, isNot(contains('Intro paragraph')));
    });

    test('entryForVersion finds a match and returns null when absent', () {
      final entries = parseChangelogFile(sample);
      expect(entryForVersion(entries, '0.32.0-alpha')?.notes,
          contains('An older thing'));
      expect(entryForVersion(entries, '9.9.9'), isNull);
    });

    test('empty / header-less input never throws and yields no entries', () {
      expect(parseChangelogFile(''), isEmpty);
      expect(parseChangelogFile('just prose\nno headers'), isEmpty);
    });
  });
}
