import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/empty_state.dart';

void main() {
  testWidgets('shows prompt text and Browse button', (tester) async {
    var browseCalled = false;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: EmptyState(onBrowse: () => browseCalled = true),
      ),
    ));

    expect(find.textContaining('Drop a video'), findsOneWidget);
    expect(find.text('Browse…'), findsOneWidget);

    await tester.tap(find.text('Browse…'));
    await tester.pump();
    expect(browseCalled, isTrue);
  });

  testWidgets('shows a join notice above the prompt when provided (#60)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: EmptyState(
          onBrowse: () {},
          notice: 'lin started playback — load a video to join',
        ),
      ),
    ));

    expect(find.textContaining('started playback'), findsOneWidget);
    // The usual prompt + Browse button still render.
    expect(find.textContaining('Drop a video'), findsOneWidget);
    expect(find.text('Browse…'), findsOneWidget);
  });
}
