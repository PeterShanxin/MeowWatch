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
}
