import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/home_screen.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('lobby stays visible until the initial join settles (#265)', (
    tester,
  ) async {
    final releaseAnswer = Completer<void>();
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final accepted = <Socket>[];
    server.listen((s) {
      accepted.add(s);
      s.listen((bytes) async {
        if (!utf8.decode(bytes, allowMalformed: true).contains('startTLS')) {
          return;
        }
        await releaseAnswer.future;
        s.add(
          utf8.encode(
            '${json.encode({
              'Error': {'message': 'unknown command startTLS'},
            })}\r\n',
          ),
        );
      }, onError: (_) {});
    });
    addTearDown(() async {
      for (final s in accepted) {
        s.destroy();
      }
      await server.close();
    });

    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MeowWatchApp(
        profiles: FakeProfileStore(),
        history: FakeHistoryStore(),
        settings: FakeSettingsStore(),
        initialTheme: MeowThemeId.cozy,
        showLaunchReveal: false,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.enterText(
      find.byKey(const Key('connect-code')),
      'sleepy-owl-13',
    );
    await tester.ensureVisible(find.byKey(const Key('connect-advanced')));
    await tester.tap(find.byKey(const Key('connect-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('connect-advanced-server')),
      '127.0.0.1',
    );
    await tester.enterText(
      find.byKey(const Key('connect-advanced-port')),
      '${server.port}',
    );
    await tester.ensureVisible(find.byKey(const Key('connect-join')));
    await tester.tap(find.byKey(const Key('connect-join')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byKey(const Key('connect-join')), findsOneWidget);
    expect(find.text('Load a video'), findsNothing);
    expect(find.text('Leave room'), findsNothing);

    releaseAnswer.complete();
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byKey(const Key('connect-join')), findsOneWidget);
    expect(find.byKey(const Key('connect-join-error')), findsOneWidget);
    expect(find.textContaining('rejected STARTTLS'), findsOneWidget);
    expect(find.text('Load a video'), findsNothing);
    expect(find.text('Leave room'), findsNothing);
  });
}
