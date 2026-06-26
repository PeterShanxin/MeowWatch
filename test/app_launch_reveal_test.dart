import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:meowwatch/ui/whats_new_dialog.dart';

import 'support/fakes.dart';

void main() {
  Widget app({required bool showReveal, bool whatsNew = false}) => MeowWatchApp(
        profiles: FakeProfileStore(),
        history: FakeHistoryStore(),
        settings: FakeSettingsStore(),
        initialTheme: MeowThemeId.cozy,
        showLaunchReveal: showReveal,
        showWhatsNew: whatsNew,
        whatsNewEntries: const [
          ChangelogEntry(
            version: '0.36.0-alpha',
            date: '2026-06-25',
            notes: '### Added\n- the launch reveal',
          ),
        ],
      );

  testWidgets('cold start shows the launch reveal over the lobby',
      (tester) async {
    await tester.pumpWidget(app(showReveal: true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('launch-reveal-splash')), findsOneWidget);
    // Let it settle so the test tears down cleanly.
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.byKey(const Key('launch-reveal-splash')), findsNothing);
  });

  testWidgets('the What\'s-new modal waits until the reveal finishes',
      (tester) async {
    await tester.pumpWidget(app(showReveal: true, whatsNew: true));
    // Mid-reveal the modal is NOT up yet (it used to pop over the splash).
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(WhatsNewDialog), findsNothing);
    // After the reveal completes, the modal appears.
    await tester.pump(const Duration(milliseconds: 2900)); // reveal completes
    await tester.pump(); // onComplete → showDialog
    await tester.pump(const Duration(milliseconds: 350)); // route transition
    expect(find.byType(WhatsNewDialog), findsOneWidget);
  });
}
