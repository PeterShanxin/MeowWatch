import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/data/saved_profile.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/home_screen.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'lobby stays visible until the initial join settles (#265)',
    (tester) async {
      final releaseAnswer = Completer<void>();
      final sawTls = Completer<void>();
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final accepted = <Socket>[];
      server.listen((s) {
        accepted.add(s);
        s.listen((bytes) async {
          if (!utf8.decode(bytes, allowMalformed: true).contains('startTLS')) {
            return;
          }
          if (!sawTls.isCompleted) sawTls.complete();
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

      final profiles = FakeProfileStore()
        ..profiles.add(
          SavedProfile(
            id: 1,
            name: 'secret-room',
            server: '127.0.0.1',
            port: server.port,
            room: 'secret-room',
            username: 'lin',
            password: null,
            lastUsedAt: DateTime(2026),
          ),
        );

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MeowWatchApp(
          profiles: profiles,
          history: FakeHistoryStore(),
          settings: FakeSettingsStore(),
          initialTheme: MeowThemeId.cozy,
          showLaunchReveal: false,
        ),
      );
      await _until(
        tester,
        () => find.text('secret-room').evaluate().isNotEmpty,
      );

      await tester.tap(find.text('secret-room'));
      await tester.pump();

      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('Load a video'), findsNothing);
      expect(find.text('Leave room'), findsNothing);

      await _until(tester, () => sawTls.isCompleted);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('Load a video'), findsNothing);

      releaseAnswer.complete();
      await _until(
        tester,
        () => find.byKey(const Key('connect-join-error')).evaluate().isNotEmpty,
      );

      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byKey(const Key('connect-join-error')), findsOneWidget);
      expect(find.textContaining('rejected STARTTLS'), findsOneWidget);
      expect(find.text('Load a video'), findsNothing);
      expect(find.text('Leave room'), findsNothing);
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
