import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:meowwatch/ui/whats_new_dialog.dart';

import 'support/fakes.dart';

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

  Widget app({
    required bool show,
    List<ChangelogEntry> entries = const [entry],
  }) =>
      MeowWatchApp(
        profiles: FakeProfileStore(),
        history: FakeHistoryStore(),
        settings: FakeSettingsStore(),
        initialTheme: MeowThemeId.cozy,
        showWhatsNew: show,
        whatsNewEntries: entries,
      );

  // Fixed pumps, not pumpAndSettle: the lobby has looping animations that never
  // settle. One extra pump runs the post-frame callback; 350ms covers the
  // showDialog route transition.
  Future<void> settleDialog(WidgetTester tester) async {
    await tester.pump(); // first frame → schedules the post-frame callback
    await tester.pump(); // runs it → showDialog
    await tester.pump(const Duration(milliseconds: 350)); // route transition
  }

  testWidgets('shows the post-update modal after first frame when enabled',
      (tester) async {
    await tester.pumpWidget(app(show: true));
    await settleDialog(tester);
    expect(find.byType(WhatsNewDialog), findsOneWidget);
    expect(find.text('a shiny hero thing', findRichText: true), findsOneWidget);
  });

  testWidgets('catch-up modal lists every version since last seen',
      (tester) async {
    await tester.pumpWidget(app(show: true, entries: const [entry, older]));
    await settleDialog(tester);
    expect(find.byType(WhatsNewDialog), findsOneWidget);
    // Newest is the hero; the older one tucks into "Earlier updates".
    expect(find.text('a shiny hero thing', findRichText: true), findsOneWidget);
    expect(find.text('EARLIER UPDATES'), findsOneWidget);
    expect(find.textContaining('v0.32.0-alpha'), findsOneWidget);
  });

  testWidgets('does not show the modal when disabled', (tester) async {
    await tester.pumpWidget(app(show: false));
    await settleDialog(tester);
    expect(find.byType(WhatsNewDialog), findsNothing);
  });

  testWidgets('does not show when enabled but no entries resolved',
      (tester) async {
    await tester.pumpWidget(app(show: true, entries: const []));
    await settleDialog(tester);
    expect(find.byType(WhatsNewDialog), findsNothing);
  });
}
