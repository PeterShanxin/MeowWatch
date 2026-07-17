import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:meowwatch/ui/whats_new_dialog.dart';

void main() {
  const entry = ChangelogEntry(
    version: '0.33.0-alpha',
    date: '2026-06-21',
    notes: '### Added\n- a shiny hero thing',
  );
  const older = ChangelogEntry(
    version: '0.32.0-alpha',
    date: '2026-06-20',
    notes: '- an older catch-up line.',
  );

  Widget host(List<ChangelogEntry> entries) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => WhatsNewDialog.show(context, entries),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('shows the just-installed highlight, a tag chip, and Got it',
      (tester) async {
    await tester.pumpWidget(host(const [entry]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('MeowWatch updated'), findsOneWidget);
    expect(find.text('a shiny hero thing', findRichText: true), findsOneWidget);
    expect(find.text('New'), findsOneWidget); // category chip from ### Added
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets(
      'multiple versions: shows an aggregate catch-up hero, with every '
      'version still listed below', (tester) async {
    await tester.pumpWidget(host(const [entry, older]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // An aggregate hero replaces the single-version hero...
    expect(find.text('2 updates installed'), findsOneWidget);
    // ...and each version, including the newest, still has its own row below.
    expect(find.text('ALL UPDATES'), findsOneWidget);
    expect(find.text('EARLIER UPDATES'), findsNothing);
    expect(find.textContaining('v0.32.0-alpha'), findsOneWidget);
  });

  testWidgets('Got it dismisses the modal', (tester) async {
    await tester.pumpWidget(host(const [entry]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewDialog), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewDialog), findsNothing);
  });
}
