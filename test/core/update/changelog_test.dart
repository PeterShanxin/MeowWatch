import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meowwatch/core/update/update_service.dart';

void main() {
  test('fetchChangelog returns only versions newer than the installed build', () async {
    final body = jsonEncode([
      {'version': '9.9.9', 'date': '2099-01-01', 'notes': '- future stuff'},
      {'version': '0.0.1', 'date': '2000-01-01', 'notes': '- ancient'},
    ]);
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('changelog.json')) {
        return http.Response(body, 200);
      }
      return http.Response('', 404);
    });
    final svc = UpdateService(baseUrl: 'https://example.test', client: mock);

    final entries = await svc.fetchChangelog();

    expect(entries.map((e) => e.version), contains('9.9.9'));
    expect(entries.map((e) => e.version), isNot(contains('0.0.1')));
    expect(entries.first.notes, contains('future stuff'));
  });

  test('fetchChangelog returns empty list on a 404', () async {
    final mock = MockClient((req) async => http.Response('', 404));
    final svc = UpdateService(baseUrl: 'https://example.test', client: mock);
    expect(await svc.fetchChangelog(), isEmpty);
  });

  test('fetchChangelog returns empty list on malformed JSON', () async {
    final mock = MockClient((req) async => http.Response('not json', 200));
    final svc = UpdateService(baseUrl: 'https://example.test', client: mock);
    expect(await svc.fetchChangelog(), isEmpty);
  });
}
