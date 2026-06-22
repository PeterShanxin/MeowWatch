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

  testWidgets('collapsed earlier row shows its category chips (not just hero)',
      (tester) async {
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
    // The older row's "Fixed" chip is visible while still collapsed, alongside
    // the hero's "New" chip — categories are scannable without expanding.
    expect(find.text('Fixed'), findsOneWidget);
    expect(find.text('New'), findsOneWidget); // hero chip
  });

  testWidgets('empty entries renders nothing', (tester) async {
    await tester.pumpWidget(host(const []));
    expect(find.byType(ChangelogView), findsOneWidget);
    expect(find.textContaining('WHAT'), findsNothing);
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
