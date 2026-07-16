// test/ui/changelog_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/platform/open_external.dart';
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
    version: '0.31.2-alpha', // a patch → infers a Fixed chip (no ### headings)
    date: '2026-06-20',
    notes: '- an older summary line. with more detail.',
  );

  testWidgets(
      'multi-version: aggregate hero combines the authored + version-inferred '
      'chips; the older row still infers its own', (tester) async {
    await tester.pumpWidget(host(const [newest, older]));

    final hero = find.byKey(changelogCatchUpHeroKey);
    expect(hero, findsOneWidget);
    // Newest's authored "New" (### Added) and older's version-inferred "Fixed"
    // (0.31.2 is a patch, and it has no ### headings of its own) both surface
    // in the aggregate hero's combined chip row.
    expect(find.descendant(of: hero, matching: find.text('New')),
        findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('Fixed')),
        findsOneWidget);
    // Each also still appears on its own version's row below (in "ALL
    // UPDATES") — the per-version breakdown isn't erased by the summary, so
    // each label legitimately shows up twice in total.
    expect(find.text('New'), findsNWidgets(2));
    expect(find.text('Fixed'), findsNWidgets(2));
    // The older row's collapsed summary is visible…
    expect(find.text('an older summary line.'), findsOneWidget);
    // …but its full detail stays collapsed (only the summary shows).
    expect(find.text('with more detail.', findRichText: true), findsNothing);
  });

  testWidgets('hero renders a descriptive chip label, not the bare category',
      (tester) async {
    await tester.pumpWidget(host(const [
      ChangelogEntry(
        version: '0.33.0-alpha',
        date: '2026-06-21',
        notes: '### Improved: Better changelog\n- prettier notes',
      ),
    ]));
    expect(find.text('Better changelog'), findsOneWidget); // custom label
    expect(find.text('Improved'), findsNothing); // not the generic word
  });

  testWidgets(
      'multi-version: a free-form version still infers its own chip on its row',
      (tester) async {
    await tester.pumpWidget(host(const [
      ChangelogEntry(
        version: '0.34.0-alpha',
        date: '2026-06-22',
        notes: '### Fixed\n- newest',
      ),
      ChangelogEntry(
        version: '0.32.0-alpha', // minor, free-form → infers New
        date: '2026-06-20',
        notes: '- a feature with no headings.',
      ),
    ]));
    final hero = find.byKey(changelogCatchUpHeroKey);
    // Aggregate hero combines the authored Fixed + the inferred New.
    expect(find.descendant(of: hero, matching: find.text('Fixed')),
        findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('New')),
        findsOneWidget);
    // Both chips also surface again on their own version's row below.
    expect(find.text('Fixed'), findsNWidgets(2));
    expect(find.text('New'), findsNWidgets(2));
  });

  testWidgets('tapping an older row expands its rendered notes', (tester) async {
    await tester.pumpWidget(host(const [newest, older]));
    // The aggregate hero already surfaces this bullet as one of its combined
    // highlights, so it's visible once even before the row is expanded.
    expect(
      find.text('an older summary line. with more detail.', findRichText: true),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('an older summary line.'));
    await tester.tap(find.text('an older summary line.'));
    await tester.pumpAndSettle();
    // After expanding, the same text legitimately renders twice: once as the
    // hero's combined highlight, once in the row's own expanded body.
    expect(
      find.text('an older summary line. with more detail.', findRichText: true),
      findsNWidgets(2),
    );
  });

  testWidgets(
      'expanded earlier row still shows its own chip exactly once (not '
      'duplicated by the expanded body)', (tester) async {
    await tester.pumpWidget(host(const [
      ChangelogEntry(
        version: '0.34.1-alpha',
        date: '2026-06-23',
        notes: '### Fixed: Modal fix\n- the hero detail',
      ),
      ChangelogEntry(
        version: '0.34.0-alpha',
        date: '2026-06-22',
        // Explicit headline so the collapsed summary line ("Glide it smoother.")
        // differs from the body bullet ("the row detail") — keeps this test
        // about the chip, not about summary/bullet overlap.
        notes: '> Glide it smoother.\n\n### Improved: Glide reflow\n'
            '- the row detail',
      ),
    ]));
    // Each custom label surfaces once in the aggregate hero's combined chips
    // and once on its own row's collapsed header — two total, not three.
    expect(find.text('Modal fix'), findsNWidgets(2));
    expect(find.text('Glide reflow'), findsNWidgets(2));
    // The aggregate hero already surfaces "the row detail" bullet as one of
    // its combined highlights, so it's visible once even before this row is
    // expanded.
    expect(find.text('the row detail', findRichText: true), findsOneWidget);
    // Expanding the older row (targeted by its version, since "Glide reflow"
    // itself now appears twice) must reveal the body bullet WITHOUT
    // re-printing the chip a third time — the expanded section heading is
    // suppressed (the chip already sits in the row header), so the chip
    // count doesn't grow, even though the bullet text now legitimately
    // renders a second time (hero's summary + the row's own expanded body).
    await tester.ensureVisible(find.textContaining('v0.34.0-alpha'));
    await tester.tap(find.textContaining('v0.34.0-alpha'));
    await tester.pumpAndSettle();
    expect(find.text('the row detail', findRichText: true), findsNWidgets(2));
    expect(find.text('Glide reflow'), findsNWidgets(2));
    expect(find.text('Modal fix'), findsNWidgets(2)); // hero + row, unaffected
  });

  testWidgets(
      'collapsed earlier row shows its category chips (not just the '
      'aggregate hero)', (tester) async {
    await tester.pumpWidget(host(const [
      ChangelogEntry(
        version: '0.33.0-alpha',
        date: '2026-06-21',
        notes: '### Added\n- newest thing',
      ),
      ChangelogEntry(
        version: '0.32.0-alpha',
        date: '2026-06-20',
        notes: '### Fixed\n- an old bug',
      ),
    ]));
    // The older row's own "Fixed" chip is visible while still collapsed, and
    // the aggregate hero above also shows both categories once each in its
    // combined chip row — two apiece in total.
    expect(find.text('Fixed'), findsNWidgets(2));
    expect(find.text('New'), findsNWidgets(2));
  });

  testWidgets('empty entries renders nothing', (tester) async {
    await tester.pumpWidget(host(const []));
    expect(find.byType(ChangelogView), findsOneWidget);
    expect(find.textContaining('WHAT'), findsNothing);
  });

  group('multi-version catch-up hero (#190)', () {
    // Two versions have two bullets each so the 4-highlight cap meaningfully
    // excludes their second bullet — proving the hero summarizes rather than
    // reprinting the whole catch-up span.
    const v4 = ChangelogEntry(
      version: '0.36.0-alpha',
      date: '2026-06-25',
      notes: '### Added\n- feature four\n- feature four b',
    );
    const v3 = ChangelogEntry(
      version: '0.35.0-alpha',
      date: '2026-06-24',
      notes: '### Added\n- feature three\n- feature three b',
    );
    const v2 = ChangelogEntry(
      version: '0.34.1-alpha',
      date: '2026-06-23',
      notes: '### Fixed\n- fix two',
    );
    const v1 = ChangelogEntry(
      version: '0.34.0-alpha',
      date: '2026-06-22',
      notes: '### Improved: Snappier lobby\n- improve one',
    );

    testWidgets(
        'shows a count header and an ALL UPDATES section, not the '
        'single-version EARLIER UPDATES label', (tester) async {
      await tester.pumpWidget(host(const [v4, v3, v2, v1]));
      expect(find.byKey(changelogCatchUpHeroKey), findsOneWidget);
      expect(find.text('4 updates installed'), findsOneWidget);
      expect(find.text('ALL UPDATES'), findsOneWidget);
      expect(find.text('EARLIER UPDATES'), findsNothing);
    });

    testWidgets('combines every category across all included versions, deduped',
        (tester) async {
      await tester.pumpWidget(host(const [v4, v3, v2, v1]));
      final hero = find.byKey(changelogCatchUpHeroKey);
      // v4 & v3 both authored ### Added → one "New" chip in the hero, not two.
      expect(find.descendant(of: hero, matching: find.text('New')),
          findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text('Fixed')),
          findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text('Snappier lobby')),
          findsOneWidget);
    });

    testWidgets(
        'shows at most 4 combined highlights, round-robin across versions '
        'before repeating any one version', (tester) async {
      await tester.pumpWidget(host(const [v4, v3, v2, v1]));
      final hero = find.byKey(changelogCatchUpHeroKey);
      // Each version's FIRST bullet is pulled in before any version's second.
      expect(
          find.descendant(
              of: hero, matching: find.text('feature four', findRichText: true)),
          findsOneWidget);
      expect(
          find.descendant(
              of: hero,
              matching: find.text('feature three', findRichText: true)),
          findsOneWidget);
      expect(
          find.descendant(
              of: hero, matching: find.text('fix two', findRichText: true)),
          findsOneWidget);
      expect(
          find.descendant(
              of: hero, matching: find.text('improve one', findRichText: true)),
          findsOneWidget);
      // The second bullets of v4/v3 didn't make the 4-item cut.
      expect(
          find.descendant(
              of: hero,
              matching: find.text('feature four b', findRichText: true)),
          findsNothing);
      expect(
          find.descendant(
              of: hero,
              matching: find.text('feature three b', findRichText: true)),
          findsNothing);
    });

    testWidgets(
        'every included version, including the newest, still gets its own '
        'row below', (tester) async {
      await tester.pumpWidget(host(const [v4, v3, v2, v1]));
      expect(find.textContaining('v0.36.0-alpha'), findsOneWidget);
      expect(find.textContaining('v0.35.0-alpha'), findsOneWidget);
      expect(find.textContaining('v0.34.1-alpha'), findsOneWidget);
      expect(find.textContaining('v0.34.0-alpha'), findsOneWidget);
    });

    testWidgets('a single version keeps the original hero exactly as-is',
        (tester) async {
      await tester.pumpWidget(host(const [v4]));
      expect(find.byKey(changelogCatchUpHeroKey), findsNothing);
      expect(find.text('ALL UPDATES'), findsNothing);
      expect(find.text('EARLIER UPDATES'), findsNothing);
      expect(find.text("WHAT'S NEW · v0.36.0-alpha"), findsOneWidget);
    });
  });

  group('hero renders the authored > summary as a headline', () {
    testWidgets('explicit headline shows above the highlights', (tester) async {
      await tester.pumpWidget(host(const [
        ChangelogEntry(
          version: '0.33.0-alpha',
          date: '2026-06-21',
          notes: '> The changelog finally reads like a changelog.\n\n'
              '### Added\n- a shiny thing',
        ),
      ]));
      // Headline AND the bullet both visible (headline is not a bullet).
      expect(
        find.text('The changelog finally reads like a changelog.'),
        findsOneWidget,
      );
      expect(find.text('a shiny thing', findRichText: true), findsOneWidget);
    });

    testWidgets('a derived summary is NOT shown as a separate headline',
        (tester) async {
      await tester.pumpWidget(host(const [
        ChangelogEntry(
          version: '0.33.0-alpha',
          date: '2026-06-21',
          notes: '### Added\n- the only bullet here.',
        ),
      ]));
      // Renders exactly once (as the bullet). A duplicate headline would make
      // this two — proving the derived summary isn't echoed above the bullets.
      expect(
        find.text('the only bullet here.', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('"Full notes" only appears when it reveals more than the highlights',
      () {
    testWidgets('short version (≤3 bullets, no prose) → no expander',
        (tester) async {
      await tester.pumpWidget(host(const [
        ChangelogEntry(
          version: '0.33.0-alpha',
          date: '2026-06-21',
          notes: '### Added\n- one\n- two\n\n### Improved\n- three',
        ),
      ]));
      // All three bullets are the highlights; nothing more to expand.
      expect(find.text('Full notes'), findsNothing);
    });

    testWidgets('more than 3 bullets → expander reveals the extras',
        (tester) async {
      await tester.pumpWidget(host(const [
        ChangelogEntry(
          version: '0.33.0-alpha',
          date: '2026-06-21',
          notes: '### Added\n- one\n- two\n- three\n- four\n- five',
        ),
      ]));
      expect(find.text('Full notes'), findsOneWidget);
      // The 4th bullet is hidden until expanded.
      expect(find.text('four', findRichText: true), findsNothing);
      await tester.tap(find.text('Full notes'));
      await tester.pumpAndSettle();
      expect(find.text('four', findRichText: true), findsOneWidget);
    });

    testWidgets('a paragraph (prose not in highlights) → expander appears',
        (tester) async {
      await tester.pumpWidget(host(const [
        ChangelogEntry(
          version: '0.33.0-alpha',
          date: '2026-06-21',
          notes: '### Fixed\n- a bug\n\nSome extra prose detail.',
        ),
      ]));
      expect(find.text('Full notes'), findsOneWidget);
      await tester.tap(find.text('Full notes'));
      await tester.pumpAndSettle();
      expect(find.text('Some extra prose detail.', findRichText: true),
          findsOneWidget);
    });
  });

  group('hero issue refs are tappable without expanding Full notes', () {
    final launched = <String>[];
    setUp(() {
      launched.clear();
      debugUrlLauncherOverride = (url) async => launched.add(url);
    });
    tearDown(() => debugUrlLauncherOverride = null);

    testWidgets('tapping a hero highlight #ref opens the issue', (tester) async {
      await tester.pumpWidget(host(const [
        ChangelogEntry(
          version: '0.33.0-alpha',
          date: '2026-06-21',
          notes: '### Added\n- a shiny thing (#136)',
        ),
      ]));

      // The ref shows in the hero highlight itself — no "Full notes" expand.
      expect(find.text('#136'), findsOneWidget);
      await tester.tap(find.text('#136'));
      await tester.pump();

      expect(launched, ['https://github.com/PeterShanxin/MeowWatch/issues/136']);
    });
  });
}
