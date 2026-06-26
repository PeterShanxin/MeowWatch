import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/tokens/motion.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('app starts on the initialTheme', (tester) async {
    final settings = FakeSettingsStore();
    await tester.pumpWidget(MeowWatchApp(
      profiles: FakeProfileStore(),
      history: FakeHistoryStore(),
      settings: settings,
      initialTheme: MeowThemeId.noir,
      showLaunchReveal: false,
    ));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.extension<MeowColors>(), MeowColors.noir);
  });

  testWidgets('theme switches melt over the slow tween', (tester) async {
    await tester.pumpWidget(MeowWatchApp(
      profiles: FakeProfileStore(),
      history: FakeHistoryStore(),
      settings: FakeSettingsStore(),
      initialTheme: MeowThemeId.cozy,
      showLaunchReveal: false,
    ));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeAnimationDuration, Motion.slow);
  });
}
