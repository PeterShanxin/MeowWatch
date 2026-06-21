# Changelog Presentation Redesign (A+B+D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the raw-text changelog panel in the updater dialog with a hero-highlights + collapsible-history layout that renders markdown and shows New/Fixed/Improved tags.

**Architecture:** A pure, dependency-free parser turns each entry's raw `notes` markdown into a render-ready model (`changelog_markup.dart`). A renderer widget paints that model with theme colors (`changelog_markdown.dart`). A panel widget composes a hero card for the newest version plus a collapsible "earlier updates" list (`changelog_view.dart`), and replaces `_changelogPanel` in `update_dialog.dart`. No new package: issue-ref links open via the existing `cmd /c start` pattern.

**Tech Stack:** Flutter (Dart 3), Material Icons, `flutter_test` + `mocktail`. No new dependencies.

## Global Constraints

- **Flutter binary (not on PATH):** `FLUTTER=C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`. All `analyze`/`test` commands below use this exact path.
- **Keep `flutter analyze` at "No issues found!"** after every task.
- **No new pub dependency.** The markdown formatter is hand-rolled for the fixed subset; external links reuse `Process.start('cmd', ['/c','start','', url], mode: detached)`.
- **Markdown subset (only these):** `**bold**`, `` `code` ``, `#<digits>` issue refs, `### Heading`, `- `/`* ` bullets, blank-line-separated paragraphs, a leading `> ` summary line.
- **Tag mapping:** `### Added`→New, `### Fixed`→Fixed, `### Changed`/`### Improved`→Improved. Tag chip colors are fixed (theme-independent, readable on all three dark themes): New `bg #33D4A574 / fg #EBCEA8 / Icons.auto_awesome`, Fixed `bg #2A7BC47F / fg #9BD89E / Icons.check_circle`, Improved `bg #2AE0B873 / fg #EBCB8E / Icons.bolt`.
- **Hero highlights:** up to 3 bullet items; fall back to the derived summary when an entry has no bullets.
- **Summaries (hybrid):** use a leading `> ...` line if present, else derive the first sentence of the first bullet/paragraph (issue refs stripped), truncated to ~90 chars with `…`.
- **Issue link base:** `https://github.com/PeterShanxin/MeowWatch/issues`.
- **Parser is total:** `parseChangelogNotes` never throws on any input.
- **Branch:** `feat/changelog-presentation` (already checked out). Commit after every task. Do not push or tag.
- **Version bump:** `0.32.0-alpha` → `0.33.0-alpha` in lockstep (`pubspec.yaml`, `lib/core/app_version.dart`, `CHANGELOG.md`) — Task 7.

## File Structure

- Create `lib/core/update/changelog_markup.dart` — model types + `parseChangelogNotes` + `parseInline` + `spansToPlainText`. Pure Dart, no Flutter import.
- Create `lib/core/platform/open_external.dart` — `openExternalUrl(String)` best-effort browser launch.
- Modify `lib/core/app_version.dart` — add `issueBaseUrl` constant; bump `appVersion` (Task 7).
- Create `lib/ui/changelog_markdown.dart` — `ChangelogMarkdown`, `ChangelogTagChip`, `IssueTapCallback`.
- Create `lib/ui/changelog_view.dart` — `ChangelogView` (hero + collapsible list).
- Modify `lib/ui/update_dialog.dart` — call `ChangelogView`, delete `_changelogPanel`.
- Create `test/core/update/changelog_markup_test.dart`, `test/ui/changelog_markdown_test.dart`, `test/ui/changelog_view_test.dart`, `test/core/platform/open_external_test.dart`.
- Modify `test/ui/update_dialog_test.dart` — update two assertions for the rendered layout.
- Modify `docs/AGENT_GUIDE.md` + `CHANGELOG.md` header pointer — Task 7.

---

### Task 1: Inline markdown parser + model types

**Files:**
- Create: `lib/core/update/changelog_markup.dart`
- Test: `test/core/update/changelog_markup_test.dart`

**Interfaces:**
- Produces: `enum ChangelogTag { added, fixed, improved }` with `String get label`; sealed `NoteSpan` (`PlainText(text)`, `BoldText(text)`, `CodeText(text)`, `IssueRef(number)`); `List<NoteSpan> parseInline(String text)`; `String spansToPlainText(List<NoteSpan> spans)`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$FLUTTER" test test/core/update/changelog_markup_test.dart`
Expected: FAIL — `changelog_markup.dart` / its symbols don't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$FLUTTER" test test/core/update/changelog_markup_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/update/changelog_markup.dart test/core/update/changelog_markup_test.dart
git commit -m "feat: inline changelog markup parser and model types"
```

---

### Task 2: Block/section parser + derivations

**Files:**
- Modify: `lib/core/update/changelog_markup.dart`
- Test: `test/core/update/changelog_markup_test.dart`

**Interfaces:**
- Consumes: `parseInline`, `spansToPlainText`, `ChangelogTag`, span types (Task 1).
- Produces: sealed `NoteBlock` (`Paragraph(spans)`, `BulletList(items)`); `class NoteSection { ChangelogTag? tag; String? title; List<NoteBlock> blocks; }`; `class ParsedNotes { String summary; List<ChangelogTag> tags; List<List<NoteSpan>> highlights; List<NoteSection> sections; }`; `ParsedNotes parseChangelogNotes(String notes)`.

- [ ] **Step 1: Write the failing test** (append to the existing test file)

```dart
// append inside main() in test/core/update/changelog_markup_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$FLUTTER" test test/core/update/changelog_markup_test.dart`
Expected: FAIL — `parseChangelogNotes`, `NoteSection`, `ParsedNotes`, `Paragraph` undefined.

- [ ] **Step 3: Write minimal implementation** (append to `changelog_markup.dart`)

```dart
// append to lib/core/update/changelog_markup.dart
import 'dart:convert' show LineSplitter;

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

  final summary = (summaryOverride != null && summaryOverride!.isNotEmpty)
      ? summaryOverride!
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
```

Note: move the `import 'dart:convert' show LineSplitter;` to the top of the file with the other directives (Dart requires imports first); keep the rest appended.

- [ ] **Step 4: Run test to verify it passes**

Run: `"$FLUTTER" test test/core/update/changelog_markup_test.dart`
Expected: PASS (Task 1 + Task 2 groups).

- [ ] **Step 5: Verify analyze is clean, then commit**

Run: `"$FLUTTER" analyze`
Expected: `No issues found!`

```bash
git add lib/core/update/changelog_markup.dart test/core/update/changelog_markup_test.dart
git commit -m "feat: parse changelog notes into sections, tags, highlights, summary"
```

---

### Task 3: External link helper + issue URL constant

**Files:**
- Create: `lib/core/platform/open_external.dart`
- Modify: `lib/core/app_version.dart`
- Test: `test/core/platform/open_external_test.dart`

**Interfaces:**
- Produces: `Future<void> openExternalUrl(String url)` (best-effort, never throws); `const String issueBaseUrl` in `app_version.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/platform/open_external_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/platform/open_external.dart';

void main() {
  // Best-effort by contract: on a non-Windows CI runner the `cmd` spawn fails
  // and is swallowed, so the call must complete without throwing on any host.
  test('openExternalUrl never throws', () async {
    await expectLater(
      openExternalUrl('https://example.test/x'),
      completes,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$FLUTTER" test test/core/platform/open_external_test.dart`
Expected: FAIL — `open_external.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/platform/open_external.dart
import 'dart:io';

/// Open [url] in the user's default browser. Best-effort and Windows-targeted:
/// reuses the same `cmd /c start` detach trick the updater uses to launch a
/// process that outlives nothing here — we just need the shell to resolve the
/// default handler. Any failure (non-Windows host, missing shell) is swallowed,
/// so this never throws and never blocks the UI.
Future<void> openExternalUrl(String url) async {
  try {
    await Process.start(
      'cmd',
      ['/c', 'start', '', url],
      mode: ProcessStartMode.detached,
    );
  } catch (_) {
    // Best-effort: a dead launcher must never disrupt the changelog view.
  }
}
```

```dart
// lib/core/app_version.dart — add near updateBaseUrl
/// Base URL for GitHub issue links rendered in the changelog (e.g. #136).
const String issueBaseUrl = 'https://github.com/PeterShanxin/MeowWatch/issues';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$FLUTTER" test test/core/platform/open_external_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/platform/open_external.dart lib/core/app_version.dart test/core/platform/open_external_test.dart
git commit -m "feat: best-effort external-url launcher and issue link base"
```

---

### Task 4: Markdown renderer widget

**Files:**
- Create: `lib/ui/changelog_markdown.dart`
- Test: `test/ui/changelog_markdown_test.dart`

**Interfaces:**
- Consumes: `NoteSection`, `NoteBlock`/`Paragraph`/`BulletList`, `NoteSpan` family, `ChangelogTag` (Tasks 1–2); `context.meow` (`MeowColors`).
- Produces: `typedef IssueTapCallback = void Function(int number)`; `class ChangelogMarkdown extends StatelessWidget { List<NoteSection> sections; IssueTapCallback onIssueTap; bool showTags; }`; `class ChangelogTagChip extends StatelessWidget { ChangelogTag tag; }`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/changelog_markdown_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/changelog_markup.dart';
import 'package:meowwatch/ui/changelog_markdown.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: child),
      );

  testWidgets('renders bullet text and a tag chip', (tester) async {
    final parsed = parseChangelogNotes('### Added\n- a shiny **thing**');
    await tester.pumpWidget(host(
      ChangelogMarkdown(sections: parsed.sections, onIssueTap: (_) {}),
    ));
    expect(find.text('New'), findsOneWidget); // chip label
    expect(find.text('a shiny thing', findRichText: true), findsOneWidget);
  });

  testWidgets('showTags: false hides chips', (tester) async {
    final parsed = parseChangelogNotes('### Fixed\n- a bug');
    await tester.pumpWidget(host(ChangelogMarkdown(
      sections: parsed.sections,
      onIssueTap: (_) {},
      showTags: false,
    )));
    expect(find.text('Fixed'), findsNothing);
  });

  testWidgets('tapping an issue ref invokes onIssueTap with the number',
      (tester) async {
    int? tapped;
    final parsed = parseChangelogNotes('- fixed it (#147)');
    await tester.pumpWidget(host(ChangelogMarkdown(
      sections: parsed.sections,
      onIssueTap: (n) => tapped = n,
    )));
    await tester.tap(find.text('#147', findRichText: true));
    expect(tapped, 147);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$FLUTTER" test test/ui/changelog_markdown_test.dart`
Expected: FAIL — `changelog_markdown.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/changelog_markdown.dart
import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/update/changelog_markup.dart';

typedef IssueTapCallback = void Function(int number);

/// Renders parsed changelog [sections] with theme colors. Bold/code/issue-ref
/// inline runs and bullet lists are painted; `### Added/Fixed/Improved` headings
/// become category chips (toggle with [showTags]).
class ChangelogMarkdown extends StatelessWidget {
  const ChangelogMarkdown({
    super.key,
    required this.sections,
    required this.onIssueTap,
    this.showTags = true,
  });

  final List<NoteSection> sections;
  final IssueTapCallback onIssueTap;
  final bool showTags;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final children = <Widget>[];
    for (final s in sections) {
      if (s.tag != null && showTags) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: ChangelogTagChip(tag: s.tag!),
        ));
      } else if (s.title != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            s.title!,
            style: TextStyle(
              color: m.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ));
      }
      for (final blk in s.blocks) {
        if (blk is Paragraph) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text.rich(_inline(blk.spans, m)),
          ));
        } else if (blk is BulletList) {
          for (final item in blk.items) {
            children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: m.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: Text.rich(_inline(item, m))),
                ],
              ),
            ));
          }
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  TextSpan _inline(List<NoteSpan> spans, MeowColors m) {
    final base = TextStyle(color: m.textDim, fontSize: 12.5, height: 1.5);
    return TextSpan(children: [
      for (final s in spans)
        switch (s) {
          PlainText(:final text) => TextSpan(text: text, style: base),
          BoldText(:final text) => TextSpan(
              text: text,
              style: base.copyWith(
                color: m.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          CodeText(:final text) => TextSpan(
              text: text,
              style: base.copyWith(
                fontFamily: 'monospace',
                color: m.accent,
                backgroundColor: m.background,
              ),
            ),
          IssueRef(:final number) => WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => onIssueTap(number),
                child: Text(
                  '#$number',
                  style: TextStyle(color: m.accent, fontSize: 11.5),
                ),
              ),
            ),
        },
    ]);
  }
}

/// A small pill for a changelog category. Colors are fixed (theme-independent)
/// so the three categories stay distinct on every dark theme.
class ChangelogTagChip extends StatelessWidget {
  const ChangelogTagChip({super.key, required this.tag});
  final ChangelogTag tag;

  @override
  Widget build(BuildContext context) {
    final style = _tagStyles[tag]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.fg),
          const SizedBox(width: 4),
          Text(
            tag.label,
            style: TextStyle(
              color: style.fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagStyle {
  const _TagStyle(this.bg, this.fg, this.icon);
  final Color bg;
  final Color fg;
  final IconData icon;
}

const Map<ChangelogTag, _TagStyle> _tagStyles = {
  ChangelogTag.added:
      _TagStyle(Color(0x33D4A574), Color(0xFFEBCEA8), Icons.auto_awesome),
  ChangelogTag.fixed:
      _TagStyle(Color(0x2A7BC47F), Color(0xFF9BD89E), Icons.check_circle),
  ChangelogTag.improved:
      _TagStyle(Color(0x2AE0B873), Color(0xFFEBCB8E), Icons.bolt),
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$FLUTTER" test test/ui/changelog_markdown_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify analyze, then commit**

Run: `"$FLUTTER" analyze`
Expected: `No issues found!`

```bash
git add lib/ui/changelog_markdown.dart test/ui/changelog_markdown_test.dart
git commit -m "feat: changelog markdown renderer with category chips and issue links"
```

---

### Task 5: ChangelogView panel (hero + collapsible list)

**Files:**
- Create: `lib/ui/changelog_view.dart`
- Test: `test/ui/changelog_view_test.dart`

**Interfaces:**
- Consumes: `ChangelogEntry` (from `update_service.dart`: `.version`, `.date`, `.notes`); `parseChangelogNotes` (Tasks 1–2); `ChangelogMarkdown`, `ChangelogTagChip` (Task 4); `openExternalUrl` + `issueBaseUrl` (Task 3); `context.meow`.
- Produces: `class ChangelogView extends StatefulWidget { List<ChangelogEntry> entries; }`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/changelog_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:meowwatch/ui/changelog_view.dart';

void main() {
  Widget host(List<ChangelogEntry> entries) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: ChangelogView(entries: entries)),
      );

  const newest = ChangelogEntry(
    version: '0.33.0-alpha',
    date: '2026-06-21',
    notes: '### Added\n- a shiny hero thing',
  );
  const older = ChangelogEntry(
    version: '0.32.0-alpha',
    date: '2026-06-20',
    notes: '- an older summary line. with more detail.',
  );

  testWidgets('hero shows newest highlight + tag; older row shows summary only',
      (tester) async {
    await tester.pumpWidget(host(const [newest, older]));

    // Hero highlight (rendered) + New chip.
    expect(find.text('a shiny hero thing', findRichText: true), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    // Earlier row summary is visible…
    expect(find.text('an older summary line.'), findsOneWidget);
    // …but the older entry's full detail is collapsed (only the summary shows).
    expect(find.text('with more detail.', findRichText: true), findsNothing);
  });

  testWidgets('tapping an older row expands its rendered notes', (tester) async {
    await tester.pumpWidget(host(const [newest, older]));
    await tester.tap(find.text('an older summary line.'));
    await tester.pumpAndSettle();
    expect(
      find.text('an older summary line. with more detail.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('empty entries renders nothing', (tester) async {
    await tester.pumpWidget(host(const []));
    expect(find.byType(ChangelogView), findsOneWidget);
    expect(find.textContaining('WHAT'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$FLUTTER" test test/ui/changelog_view_test.dart`
Expected: FAIL — `changelog_view.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/changelog_view.dart
import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/platform/open_external.dart';
import '../core/theme/meow_context.dart';
import '../core/update/changelog_markup.dart';
import '../core/update/update_service.dart';
import 'changelog_markdown.dart';

/// The redesigned "What's new" panel: a highlights hero for the newest version
/// (A+D) plus a collapsible "earlier updates" list (B), all rendered markdown
/// with category chips (A). Replaces the old raw-text `_changelogPanel`.
class ChangelogView extends StatefulWidget {
  const ChangelogView({super.key, required this.entries});

  final List<ChangelogEntry> entries;

  @override
  State<ChangelogView> createState() => _ChangelogViewState();
}

class _ChangelogViewState extends State<ChangelogView> {
  final Set<int> _expanded = <int>{};
  bool _heroExpanded = false;

  void _onIssueTap(int n) => openExternalUrl('$issueBaseUrl/$n');

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final m = context.meow;
    final parsed = widget.entries.map((e) => parseChangelogNotes(e.notes)).toList();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: m.border.withValues(alpha: 0.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _hero(m, widget.entries.first, parsed.first),
            if (widget.entries.length > 1) ...[
              const SizedBox(height: 12),
              Text(
                'EARLIER UPDATES',
                style: TextStyle(
                  color: m.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              for (var i = 1; i < widget.entries.length; i++)
                _earlierRow(m, i, widget.entries[i], parsed[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero(MeowColors m, ChangelogEntry e, ParsedNotes p) {
    final highlights = p.highlights.take(3).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: m.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "WHAT'S NEW · v${e.version}",
                  style: TextStyle(
                    color: m.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                _formatDate(e.date),
                style: TextStyle(color: m.textDim, fontSize: 11),
              ),
            ],
          ),
          if (p.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in p.tags) ChangelogTagChip(tag: t)],
            ),
          ],
          const SizedBox(height: 4),
          if (highlights.isEmpty)
            _bullet(m, [PlainText(p.summary)])
          else
            for (final h in highlights) _bullet(m, h),
          GestureDetector(
            onTap: () => setState(() => _heroExpanded = !_heroExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Full notes',
                    style: TextStyle(color: m.accent, fontSize: 12.5),
                  ),
                  Icon(
                    _heroExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: m.accent,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_heroExpanded)
            ChangelogMarkdown(sections: p.sections, onIssueTap: _onIssueTap),
        ],
      ),
    );
  }

  Widget _bullet(MeowColors m, List<NoteSpan> spans) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: m.accent, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  for (final s in spans)
                    switch (s) {
                      PlainText(:final text) => TextSpan(text: text),
                      BoldText(:final text) => TextSpan(
                          text: text,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      CodeText(:final text) => TextSpan(text: text),
                      IssueRef(:final number) => TextSpan(text: '#$number'),
                    },
                ],
                style: TextStyle(color: m.textPrimary, fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _earlierRow(MeowColors m, int i, ChangelogEntry e, ParsedNotes p) {
    final open = _expanded.contains(i);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (open) {
              _expanded.remove(i);
            } else {
              _expanded.add(i);
            }
          }),
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: m.border)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'v${e.version} · ${_formatDate(e.date)}',
                        style: TextStyle(
                          color: m.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (p.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            p.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: m.textDim, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: m.textDim,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChangelogMarkdown(
              sections: p.sections,
              onIssueTap: _onIssueTap,
            ),
          ),
      ],
    );
  }

  /// "2026-06-21" → "Jun 21, 2026"; falls back to the raw string on any parse
  /// failure (defensive — a malformed date must never break the view).
  String _formatDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    final y = int.tryParse(parts[0]);
    final mo = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || mo == null || d == null || mo < 1 || mo > 12) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[mo - 1]} $d, $y';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$FLUTTER" test test/ui/changelog_view_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify analyze, then commit**

Run: `"$FLUTTER" analyze`
Expected: `No issues found!`

```bash
git add lib/ui/changelog_view.dart test/ui/changelog_view_test.dart
git commit -m "feat: changelog view with highlights hero and collapsible history"
```

---

### Task 6: Wire ChangelogView into UpdateDialog + fix existing tests

**Files:**
- Modify: `lib/ui/update_dialog.dart` (replace `_changelogPanel` usages at ~line 163 and ~line 180; delete `_changelogPanel` at ~line 277)
- Modify: `test/ui/update_dialog_test.dart` (two assertions, ~lines 54-55)

**Interfaces:**
- Consumes: `ChangelogView` (Task 5).

- [ ] **Step 1: Update the existing widget test for the new layout**

In `test/ui/update_dialog_test.dart`, the "shows the changelog in the up-to-date state" test currently asserts the raw bullet text. With the redesign the newest entry becomes the hero (its bullet rendered) and the older entry collapses to its summary. Replace the two assertions:

```dart
// was:
//   expect(find.text('- shiny thing'), findsOneWidget);
//   expect(find.text('- older thing'), findsOneWidget);
// now:
    expect(find.text('shiny thing', findRichText: true), findsOneWidget);
    expect(find.text('older thing'), findsOneWidget); // older entry's summary row
```

(The `find.text("What's new")` and the empty-changelog assertions stay unchanged.)

- [ ] **Step 2: Run the test to verify it now fails against the OLD dialog**

Run: `"$FLUTTER" test test/ui/update_dialog_test.dart`
Expected: FAIL — the old `_changelogPanel` renders `- shiny thing` as one `Text`, so `find.text('shiny thing', findRichText: true)` does not match yet. This proves the test now targets the new behavior.

- [ ] **Step 3: Wire in ChangelogView**

Add the import at the top of `lib/ui/update_dialog.dart`:

```dart
import 'changelog_view.dart';
```

In the `upToDate` phase, replace the `_changelogPanel(m)` call (inside the `if (_service.changelog.isNotEmpty)` block) with:

```dart
              ChangelogView(entries: _service.changelog),
```

In the `updateAvailable` phase, replace the `_changelogPanel(m)` call (inside the `if (_service.changelog.isNotEmpty)` block) with:

```dart
              ChangelogView(entries: _service.changelog),
```

Then delete the entire `_changelogPanel` method (the `Widget _changelogPanel(dynamic m) { ... }` block, ~lines 277-319).

- [ ] **Step 4: Run the dialog test + full suite to verify green**

Run: `"$FLUTTER" test test/ui/update_dialog_test.dart`
Expected: PASS.

Run: `"$FLUTTER" test`
Expected: All tests pass (markup, markdown, view, dialog, changelog fetch, plus the rest of the suite).

- [ ] **Step 5: Verify analyze, then commit**

Run: `"$FLUTTER" analyze`
Expected: `No issues found!` (confirms the deleted `_changelogPanel` left no dangling references and no unused imports/`TypeScale`/`Radii`/`Spacing` symbols — remove any that analyze flags as unused).

```bash
git add lib/ui/update_dialog.dart test/ui/update_dialog_test.dart
git commit -m "feat: use ChangelogView in the update dialog"
```

---

### Task 7: Version bump + new-style CHANGELOG entry + writing convention

**Files:**
- Modify: `pubspec.yaml:19`
- Modify: `lib/core/app_version.dart` (`appVersion`)
- Modify: `CHANGELOG.md` (new top entry + one-line style pointer near the top)
- Modify: `docs/AGENT_GUIDE.md` (add a "Changelog writing style" subsection)

**Interfaces:** none (release metadata + docs).

- [ ] **Step 1: Bump the version in lockstep**

`pubspec.yaml` line 19:

```yaml
version: 0.33.0-alpha+1
```

`lib/core/app_version.dart` — set the version constant:

```dart
const String appVersion = '0.33.0-alpha';
```

- [ ] **Step 2: Add the new CHANGELOG entry (dogfood the new style)**

Add at the top of `CHANGELOG.md` (below the intro comment, above `## [0.32.0-alpha]`):

```markdown
## [0.33.0-alpha] - 2026-06-21
> The changelog finally reads like a changelog.

### Added
- A redesigned **What's new** screen: the newest update sits up top with quick highlights and New / Fixed / Improved tags, while older versions tuck into a tidy list you can open one at a time.

### Improved
- Release notes are now properly formatted — bold, bullets, and tappable issue links — instead of showing the raw `**` and `###` marks.
```

- [ ] **Step 3: Add a one-line style pointer near the top of CHANGELOG.md**

Just under the existing intro paragraph in `CHANGELOG.md`, add:

```markdown
> Writing style: see "Changelog writing style" in `docs/AGENT_GUIDE.md`. Write
> user-facing notes (keep internal mechanism in the commit), use `### Added` /
> `### Fixed` / `### Improved` sections, and optionally lead with a `> one-line
> summary`.
```

- [ ] **Step 4: Document the convention in AGENT_GUIDE.md**

Add a subsection under the Workflow/Versioning area of `docs/AGENT_GUIDE.md`:

```markdown
### Changelog writing style

The in-app "What's new" screen renders each version's notes. Write them for the
end user:

- Lead with an optional `> one-line summary` — it becomes the hero/row headline.
  Omit it and the app derives one from the first line.
- Group changes under `### Added`, `### Fixed`, or `### Improved` so the New /
  Fixed / Improved chips appear. `### Changed` also maps to Improved.
- Keep internal mechanism ("Future", "single-flight", "robocopy") in the commit
  message, not the note. Describe what the user sees change.
- Issue refs `(#NNN)` render as tappable links — leave them in.
- Supported formatting: `**bold**`, `` `code` ``, bullets, paragraphs.
```

- [ ] **Step 5: Verify everything green**

Run: `"$FLUTTER" analyze`
Expected: `No issues found!`

Run: `"$FLUTTER" test`
Expected: full suite passes.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml lib/core/app_version.dart CHANGELOG.md docs/AGENT_GUIDE.md
git commit -m "feat: changelog presentation redesign — version bump and writing convention"
```

---

## Self-Review

**1. Spec coverage:**
- Render markdown → Tasks 1, 4. ✅
- Hero highlights (D) → Task 5 `_hero`. ✅
- Collapsible earlier list (B) → Task 5 `_earlierRow`. ✅
- Category tags (A) → Tasks 2 (derive), 4 (chip). ✅
- Hybrid summary (auto + `>` override) → Task 2 `_deriveSummary` + override. ✅
- No new dependency / built-in formatter → Tasks 1–2; external links via `cmd /c start` → Task 3. ✅
- No pipeline change → confirmed; everything parses client-side from `notes`. ✅
- Total parser (never throws) → Task 2 empty/whitespace test. ✅
- Empty changelog fallback → Task 5 `SizedBox.shrink` + Task 6 keeps the dialog's `isNotEmpty` guard. ✅
- Writing convention in AGENT_GUIDE (not just memory) → Task 7. ✅
- Version bump in lockstep → Task 7. ✅

**2. Placeholder scan:** No TBD/TODO; every code step contains full code; commands have expected output. ✅

**3. Type consistency:** `parseChangelogNotes`/`ParsedNotes`/`NoteSection`/`NoteBlock`(`Paragraph`/`BulletList`)/`NoteSpan`(`PlainText`/`BoldText`/`CodeText`/`IssueRef`)/`ChangelogTag`/`parseInline`/`spansToPlainText` used identically across Tasks 1–6. `ChangelogMarkdown(sections, onIssueTap, showTags)` and `ChangelogTagChip(tag)` consistent between Tasks 4–5. `openExternalUrl`/`issueBaseUrl` consistent between Tasks 3 and 5. `ChangelogView(entries)` consistent between Tasks 5–6. ✅
