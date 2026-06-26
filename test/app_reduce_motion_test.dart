import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';

import 'support/fakes.dart';

void main() {
  Widget app({required bool reduceMotion}) => MeowWatchApp(
        profiles: FakeProfileStore(),
        history: FakeHistoryStore(),
        settings: FakeSettingsStore(),
        initialTheme: MeowThemeId.cozy,
        initialReduceMotion: reduceMotion,
        showLaunchReveal: true,
      );

  testWidgets('the reduce-motion setting flows into context.reduceMotion '
      '(launch splash is skipped)', (tester) async {
    await tester.pumpWidget(app(reduceMotion: true));
    await tester.pump(); // post-frame complete
    expect(find.byKey(const Key('launch-reveal-splash')), findsNothing);
  });

  testWidgets('with the setting off, the launch splash plays', (tester) async {
    await tester.pumpWidget(app(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('launch-reveal-splash')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900)); // settle for teardown
  });
}
