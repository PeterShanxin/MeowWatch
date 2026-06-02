import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/window_close_handler.dart';

void main() {
  // Pump a button that opens the close-confirm dialog and records its result.
  Future<UpdateCloseChoice?> openAndPick(
    WidgetTester tester,
    String tapLabel,
  ) async {
    UpdateCloseChoice? picked;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showUpdateOnCloseDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Install update before closing?'), findsOneWidget);

    await tester.tap(find.text(tapLabel));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('"Install & quit" returns installAndQuit', (tester) async {
    expect(
      await openAndPick(tester, 'Install & quit'),
      UpdateCloseChoice.installAndQuit,
    );
  });

  testWidgets('"Just quit" returns justQuit', (tester) async {
    expect(
      await openAndPick(tester, 'Just quit'),
      UpdateCloseChoice.justQuit,
    );
  });

  testWidgets('dismissing the dialog counts as cancel (stay open)',
      (tester) async {
    UpdateCloseChoice? picked;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showUpdateOnCloseDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the barrier to dismiss without choosing.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, UpdateCloseChoice.cancel);
  });

  testWidgets('the installing modal shows a spinner and cannot be dismissed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInstallingUpdateDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(); // start the dialog route
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Installing update'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Esc / back must not dismiss it (PopScope canPop: false).
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.textContaining('Installing update'), findsOneWidget);
  });
}
