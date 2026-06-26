import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/settings/settings_panel.dart';

void main() {
  testWidgets('reflects value and fires onChanged on tap', (tester) async {
    bool? picked;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ReduceMotionControl(value: false, onChanged: (v) => picked = v),
      ),
    ));
    await tester.tap(find.byKey(const Key('reduce-motion-on')));
    expect(picked, isTrue);

    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ReduceMotionControl(value: true, onChanged: (v) => picked = v),
      ),
    ));
    await tester.tap(find.byKey(const Key('reduce-motion-off')));
    expect(picked, isFalse);
  });
}
