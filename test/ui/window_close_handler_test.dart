import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:meowwatch/ui/app_close_hook.dart';
import 'package:meowwatch/ui/window_close_handler.dart';

void main() {
  // Pump a button that opens the close-confirm dialog and records its result.
  Future<UpdateCloseChoice?> openAndPick(
    WidgetTester tester,
    String tapLabel,
  ) async {
    UpdateCloseChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
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
    expect(await openAndPick(tester, 'Just quit'), UpdateCloseChoice.justQuit);
  });

  testWidgets('dismissing the dialog counts as cancel (stay open)', (
    tester,
  ) async {
    UpdateCloseChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the barrier to dismiss without choosing.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, UpdateCloseChoice.cancel);
  });

  testWidgets('the installing modal shows a spinner and cannot be dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInstallingUpdateDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
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

  test('handleClose announces a leave before tearing down (#92)', () async {
    final order = <String>[];
    appCloseHook.value = () async => order.add('leave');
    addTearDown(() => appCloseHook.value = null);

    final handler = WindowCloseHandler(
      navigatorKey: GlobalKey<NavigatorState>(),
      service: UpdateService.forTest(), // phase idle → no update dialog
      hideWindow: () async => order.add('hide'),
      destroyWindow: () async => order.add('destroy'),
      exitProcess: (_) => order.add('exit'),
    );

    await handler.handleClose();

    // The leave must be announced before the window is destroyed, else the
    // socket dies first and peers see "lost connection" (#92).
    expect(order, ['hide', 'leave', 'destroy', 'exit']);
  });

  test('handleClose awaits the bounded room leave before destroy (#148)', () async {
    final order = <String>[];
    // A leave with an async gap stands in for the real one: send the leave
    // packet, then await disconnectForAppClose()'s bounded socket flush.
    appCloseHook.value = () async {
      order.add('leave-start');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      order.add('leave-done');
    };
    addTearDown(() => appCloseHook.value = null);

    final handler = WindowCloseHandler(
      navigatorKey: GlobalKey<NavigatorState>(),
      service: UpdateService.forTest(),
      hideWindow: () async => order.add('hide'),
      destroyWindow: () async => order.add('destroy'),
      exitProcess: (_) => order.add('exit'),
    );

    await handler.handleClose();

    // The leave (including its socket flush) is awaited to completion before the
    // window is destroyed and the process exits — otherwise a fast destroy/exit
    // can kill the process mid-flush and peers see a dropped connection instead
    // of the clean leave (Codex P2 on #148). Boundedness against a *wedged*
    // leave is covered by the timeout test below.
    expect(order, ['hide', 'leave-start', 'leave-done', 'destroy', 'exit']);
  });

  test('handleClose exits even when room leave never completes', () async {
    final order = <String>[];
    appCloseHook.value = () async {
      order.add('leave-start');
      await Completer<void>().future;
    };
    addTearDown(() => appCloseHook.value = null);

    final handler = WindowCloseHandler(
      navigatorKey: GlobalKey<NavigatorState>(),
      service: UpdateService.forTest(),
      hideWindow: () async => order.add('hide'),
      destroyWindow: () async => order.add('destroy'),
      exitProcess: (_) => order.add('exit'),
      closeHookTimeout: const Duration(milliseconds: 1),
    );

    await handler.handleClose();

    expect(order, ['hide', 'leave-start', 'destroy', 'exit']);
  });

  test('handleClose exits even when hiding the window hangs', () async {
    appCloseHook.value = null;
    final order = <String>[];

    final handler = WindowCloseHandler(
      navigatorKey: GlobalKey<NavigatorState>(),
      service: UpdateService.forTest(),
      hideWindow: () async {
        order.add('hide-start');
        await Completer<void>().future;
      },
      destroyWindow: () async => order.add('destroy'),
      exitProcess: (_) => order.add('exit'),
      closeStepTimeout: const Duration(milliseconds: 1),
    );

    await handler.handleClose();

    expect(order, ['hide-start', 'destroy', 'exit']);
  });

  test('hard exit fires if a close step wedges before normal exit', () async {
    appCloseHook.value = null;
    final order = <String>[];

    final handler = WindowCloseHandler(
      navigatorKey: GlobalKey<NavigatorState>(),
      service: UpdateService.forTest(),
      hideWindow: () async {
        order.add('hide-start');
        await Completer<void>().future;
      },
      destroyWindow: () async => order.add('destroy'),
      exitProcess: (_) => order.add('exit'),
      closeStepTimeout: const Duration(milliseconds: 30),
      hardExitTimeout: const Duration(milliseconds: 1),
    );

    final close = handler.handleClose();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(order, ['hide-start', 'exit']);

    await close;
    expect(order, ['hide-start', 'exit', 'destroy']);
  });

  test('handleClose without a hook still destroys the window', () async {
    appCloseHook.value = null;
    final order = <String>[];

    final handler = WindowCloseHandler(
      navigatorKey: GlobalKey<NavigatorState>(),
      service: UpdateService.forTest(),
      hideWindow: () async {},
      destroyWindow: () async => order.add('destroy'),
      exitProcess: (_) => order.add('exit'),
    );

    await handler.handleClose();

    expect(order, ['destroy', 'exit']);
  });
}
