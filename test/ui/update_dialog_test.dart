import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meowwatch/core/app_version.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:meowwatch/ui/update_dialog.dart';

void main() {
  // latest.json reporting the installed version → the dialog lands in the
  // up-to-date phase. Both arch keys so it works on x64 and arm64 hosts.
  String latestJson(String version) => jsonEncode({
        'version': version,
        'assets': {
          'windows-x64': {'url': 'https://example.test/a.zip', 'sha256': 'x'},
          'windows-arm64': {'url': 'https://example.test/a.zip', 'sha256': 'x'},
        },
      });

  MockClient upToDateClient({required String changelog}) => MockClient((req) async {
        if (req.url.path.endsWith('latest.json')) {
          return http.Response(latestJson(appVersion), 200);
        }
        if (req.url.path.endsWith('changelog.json')) {
          return http.Response(changelog, 200);
        }
        return http.Response('', 404);
      });

  Widget host(UpdateService service) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: UpdateDialog(service: service)),
      );

  testWidgets('shows the changelog in the up-to-date state', (tester) async {
    final changelog = jsonEncode([
      {'version': '0.1.5-alpha', 'date': '2026-05-31', 'notes': '- shiny thing'},
      {'version': '0.1.4-alpha', 'date': '2026-05-30', 'notes': '- older thing'},
    ]);
    final svc = UpdateService.forTest(
      baseUrl: 'https://example.test',
      client: upToDateClient(changelog: changelog),
    );

    await tester.pumpWidget(host(svc));
    await tester.pumpAndSettle();

    expect(find.text("You're up to date!"), findsOneWidget);
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('- shiny thing'), findsOneWidget);
    expect(find.text('- older thing'), findsOneWidget);
  });

  testWidgets('up-to-date with no changelog hides the "What\'s new" section',
      (tester) async {
    final svc = UpdateService.forTest(
      baseUrl: 'https://example.test',
      client: upToDateClient(changelog: '[]'),
    );

    await tester.pumpWidget(host(svc));
    await tester.pumpAndSettle();

    expect(find.text("You're up to date!"), findsOneWidget);
    expect(find.text("What's new"), findsNothing);
  });

  // latest.json advertising a version far above the installed one, plus a tiny
  // zip body, so a download can run to completion in a test.
  MockClient updateAvailableClient() => MockClient((req) async {
        if (req.url.path.endsWith('latest.json')) {
          return http.Response(
            jsonEncode({
              'version': '99.0.0',
              'assets': {
                'windows-x64': {'url': 'https://example.test/a.zip', 'sha256': 'x'},
                'windows-arm64': {'url': 'https://example.test/a.zip', 'sha256': 'x'},
              },
            }),
            200,
          );
        }
        if (req.url.path.endsWith('changelog.json')) {
          return http.Response('[]', 200);
        }
        if (req.url.path.endsWith('a.zip')) {
          return http.Response.bytes([1, 2, 3, 4], 200);
        }
        return http.Response('', 404);
      });

  testWidgets('a download that finished while the dialog was closed is still '
      'there when it reopens (#22)', (tester) async {
    final svc = UpdateService.forTest(
      baseUrl: 'https://example.test',
      client: updateAvailableClient(),
    );

    // Drive the download to completion with no dialog mounted — the singleton
    // keeps running in the background after the user dismisses it.
    await svc.checkUpdateForDialog();
    expect(svc.phase, UpdatePhase.updateAvailable);
    await svc.startDownload();
    expect(svc.phase, UpdatePhase.readyToInstall);
    expect(svc.downloadedZipPath, isNotNull);

    // Reopening the dialog must surface the finished download, not restart the
    // check and throw the progress away.
    await tester.pumpWidget(host(svc));
    await tester.pumpAndSettle();
    expect(svc.phase, UpdatePhase.readyToInstall);
    expect(find.text('Download complete!'), findsOneWidget);
    expect(find.text('Install & Restart'), findsOneWidget);
  });

  test('checkUpdateForDialog coalesces concurrent calls (#47)', () async {
    var latestChecks = 0;
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('latest.json')) {
        latestChecks++;
        return http.Response(latestJson(appVersion), 200);
      }
      if (req.url.path.endsWith('changelog.json')) {
        return http.Response('[]', 200);
      }
      return http.Response('', 404);
    });
    final svc = UpdateService.forTest(baseUrl: 'https://example.test', client: mock);
    addTearDown(svc.dispose);

    // Fire two checks without awaiting the first: the second sees phase ==
    // checking and bows out, so only one network round-trip happens.
    final first = svc.checkUpdateForDialog();
    final second = svc.checkUpdateForDialog();
    await Future.wait([first, second]);

    expect(latestChecks, 1);
    expect(svc.phase, UpdatePhase.upToDate);
  });
}
