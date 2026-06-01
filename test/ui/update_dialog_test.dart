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
}
