import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meowwatch/core/app_version.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:meowwatch/ui/version_badge.dart';

void main() {
  // latest.json for a given version. Both arch keys so it works on x64/arm64.
  String latestJson(String version) => jsonEncode({
        'version': version,
        'assets': {
          'windows-x64': {'url': 'https://example.test/a.zip', 'sha256': 'x'},
          'windows-arm64': {'url': 'https://example.test/a.zip', 'sha256': 'x'},
        },
        'release_notes': 'shiny',
        'release_date': '2026-05-31',
      });

  // Client that reports [version] as the latest available release.
  MockClient clientReporting(String version) => MockClient((req) async {
        if (req.url.path.endsWith('latest.json')) {
          return http.Response(latestJson(version), 200);
        }
        if (req.url.path.endsWith('changelog.json')) {
          return http.Response('[]', 200);
        }
        return http.Response('', 404);
      });

  // Client that always fails the check (server unreachable).
  MockClient failingClient() =>
      MockClient((req) async => http.Response('', 500));

  UpdateService Function() factoryFor(http.Client client) =>
      () => UpdateService.forTest(baseUrl: 'https://example.test', client: client);

  Widget host(UpdateService Function() serviceFactory) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: VersionBadge(serviceFactory: serviceFactory),
        ),
      );

  final dotFinder = find.byKey(const Key('version-badge-update-dot'));

  setUp(VersionBadge.resetForTest);
  tearDown(VersionBadge.resetForTest);

  testWidgets('update available → shows dot and toast', (tester) async {
    await tester.pumpWidget(host(factoryFor(clientReporting('99.0.0'))));
    await tester.pumpAndSettle();

    expect(dotFinder, findsOneWidget);
    expect(find.text('🐾 New version available!'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Update'), findsOneWidget);
  });

  testWidgets('update toast can be dismissed via its close button (#61)',
      (tester) async {
    await tester.pumpWidget(host(factoryFor(clientReporting('99.0.0'))));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    final closeBtn = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byIcon(Icons.close),
    );
    expect(closeBtn, findsOneWidget);

    await tester.tap(closeBtn);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('tapping the toast Update action opens the UpdateDialog',
      (tester) async {
    await tester.pumpWidget(host(factoryFor(clientReporting('99.0.0'))));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SnackBarAction, 'Update'));
    await tester.pumpAndSettle();

    expect(find.text('MeowWatch Updates'), findsOneWidget);
  });

  testWidgets('up to date → no dot, no toast', (tester) async {
    await tester.pumpWidget(host(factoryFor(clientReporting(appVersion))));
    await tester.pumpAndSettle();

    expect(dotFinder, findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('failed check → no dot', (tester) async {
    await tester.pumpWidget(host(factoryFor(failingClient())));
    await tester.pumpAndSettle();

    expect(dotFinder, findsNothing);
  });

  testWidgets('records the update even if the badge unmounts mid-check',
      (tester) async {
    // Hold the check open until after the first badge unmounts.
    final gate = Completer<http.Response>();
    final client = MockClient((req) async {
      if (req.url.path.endsWith('latest.json')) return gate.future;
      return http.Response('', 404);
    });
    final factory = factoryFor(client);

    await tester.pumpWidget(host(factory));
    await tester.pump(); // kick off the in-flight check

    // Tear the badge down before the check resolves.
    await tester.pumpWidget(const SizedBox());
    gate.complete(http.Response(latestJson('99.0.0'), 200));
    await tester.pumpAndSettle();

    // A fresh badge mounts: it must not re-check, but must show the dot,
    // proving the result was recorded despite the earlier unmount.
    await tester.pumpWidget(host(factory));
    await tester.pump();

    expect(dotFinder, findsOneWidget);
  });
}
