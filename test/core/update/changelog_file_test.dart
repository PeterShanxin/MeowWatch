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

  group('entriesForWhatsNew', () {
    const many = '''
## [0.33.0-alpha] - 2026-06-21
- newest

## [0.32.0-alpha] - 2026-06-20
- middle

## [0.31.0-alpha] - 2026-06-19
- oldest
''';

    test('returns every version newer than lastSeen, newest first', () {
      final got = entriesForWhatsNew(
        parseChangelogFile(many),
        lastSeen: '0.31.0-alpha',
        current: '0.33.0-alpha',
      );
      expect(got.map((e) => e.version), ['0.33.0-alpha', '0.32.0-alpha']);
    });

    test('one version behind → just that version', () {
      final got = entriesForWhatsNew(
        parseChangelogFile(many),
        lastSeen: '0.32.0-alpha',
        current: '0.33.0-alpha',
      );
      expect(got.map((e) => e.version), ['0.33.0-alpha']);
    });

    test('caps at current — never previews a version the user lacks', () {
      final got = entriesForWhatsNew(
        parseChangelogFile(many),
        lastSeen: '0.31.0-alpha',
        current: '0.32.0-alpha', // running an older build than the file's top
      );
      expect(got.map((e) => e.version), ['0.32.0-alpha']);
    });

    test('null/blank lastSeen falls back to just the current entry', () {
      final entries = parseChangelogFile(many);
      expect(
        entriesForWhatsNew(entries, lastSeen: null, current: '0.33.0-alpha')
            .map((e) => e.version),
        ['0.33.0-alpha'],
      );
      expect(
        entriesForWhatsNew(entries, lastSeen: '  ', current: '0.33.0-alpha')
            .map((e) => e.version),
        ['0.33.0-alpha'],
      );
    });

    test('current absent and no span → empty list (modal skipped)', () {
      final got = entriesForWhatsNew(
        parseChangelogFile(many),
        lastSeen: '9.9.9',
        current: '9.9.9',
      );
      expect(got, isEmpty);
    });
  });
}
