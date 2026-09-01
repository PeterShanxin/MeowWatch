import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/saved_profile.dart';
import 'package:meowwatch/core/sync/endpoint_discovery.dart';
import 'package:meowwatch/core/sync/syncplay_endpoints.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/connect/connect_screen.dart';
import 'package:meowwatch/ui/version_badge.dart';

import '../../support/fakes.dart';

/// #234 — which launches get a discovered endpoint and which are pinned.
///
/// The rule the whole feature rests on: MeowWatch may re-resolve an endpoint it
/// chose itself, and may never move one the user or a friend's code named. Two
/// peers can only meet if the answer to "where is this room" is the same on both
/// machines.
const _default = SyncplayEndpoint(host: 'syncplay.pl', port: 8995);
const _moved = SyncplayEndpoint(host: 'syncplay.pl', port: 8997);
const _selfHosted = SyncplayEndpoint(host: 'cozy.example.net', port: 8999);

/// Records what the lobby asked discovery for, and answers with [result].
class _FakeResolver {
  _FakeResolver(this.result);

  final SyncplayEndpoint? result;
  int calls = 0;
  final List<SyncplayEndpoint?> preferred = <SyncplayEndpoint?>[];

  Future<SyncplayEndpoint?> resolve({SyncplayEndpoint? preferred}) async {
    calls++;
    this.preferred.add(preferred);
    return result;
  }
}

void main() {
  late FakeProfileStore profiles;
  late FakeHistoryStore history;
  RoomConfig? connected;

  Future<void> pump(
    WidgetTester tester, {
    required ResolveSyncplayEndpoint resolveEndpoint,
  }) async {
    connected = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: ConnectScreen(
          profiles: profiles,
          history: history,
          settings: FakeSettingsStore(),
          currentTheme: MeowThemeId.cozy,
          onThemeChanged: (_) {},
          resolveEndpoint: resolveEndpoint,
          onConnect: (config) async {
            connected = config;
            return null;
          },
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tapStart(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('connect-start-new')));
    await tester.tap(find.byKey(const Key('connect-start-new')));
    await tester.pumpAndSettle();
  }

  Future<void> setAdvanced(
    WidgetTester tester, {
    String? server,
    String? port,
  }) async {
    await tester.tap(find.byKey(const Key('connect-advanced')));
    await tester.pumpAndSettle();
    if (server != null) {
      await tester.enterText(
        find.byKey(const Key('connect-advanced-server')),
        server,
      );
    }
    if (port != null) {
      await tester.enterText(
        find.byKey(const Key('connect-advanced-port')),
        port,
      );
    }
    await tester.pump();
  }

  setUp(() {
    profiles = FakeProfileStore();
    history = FakeHistoryStore();
    VersionBadge.resetForTest();
  });

  group('starting a new room', () {
    testWidgets('joins the endpoint discovery picked', (tester) async {
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);

      await tapStart(tester);

      expect(resolver.calls, 1);
      expect(
        resolver.preferred.single,
        isNull,
        reason: 'a brand-new room has no address of its own yet',
      );
      expect(connected!.server, _moved.host);
      expect(connected!.port, _moved.port);
    });

    testWidgets('bakes the resolved endpoint into the shared code', (
      tester,
    ) async {
      // The joining peer must land on the server the host actually reached, so
      // the code has to name it rather than say "the default".
      await pump(tester, resolveEndpoint: _FakeResolver(_moved).resolve);

      await tapStart(tester);

      expect(find.textContaining('@syncplay.pl:8997'), findsOneWidget);
      expect(find.textContaining(connected!.room), findsOneWidget);
    });

    testWidgets('leaves the shared code bare on the default endpoint', (
      tester,
    ) async {
      // Unchanged from before discovery existed: a bare magic sentence still
      // means the default public endpoint, so old and new copies of the app
      // read each other's codes the same way.
      await pump(tester, resolveEndpoint: _FakeResolver(_default).resolve);

      await tapStart(tester);

      expect(find.textContaining('@'), findsNothing);
      expect(connected!.server, _default.host);
      expect(connected!.port, _default.port);
    });

    testWidgets('never resolves over an Advanced server', (tester) async {
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);
      await setAdvanced(tester, server: 'my.lan', port: '1234');

      await tapStart(tester);

      expect(resolver.calls, 0);
      expect(connected!.server, 'my.lan');
      expect(connected!.port, 1234);
    });

    testWidgets('never resolves over an Advanced port alone', (tester) async {
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);
      await setAdvanced(tester, port: '8999');

      await tapStart(tester);

      expect(resolver.calls, 0);
      expect(connected!.server, 'syncplay.pl');
      expect(connected!.port, 8999);
    });

    testWidgets('reports the outage instead of asking for a server', (
      tester,
    ) async {
      await pump(tester, resolveEndpoint: _FakeResolver(null).resolve);

      await tapStart(tester);

      expect(connected, isNull, reason: 'nowhere to connect to');
      expect(find.text(kNoSyncplayServerMessage), findsOneWidget);
      expect(
        find.textContaining('Check Advanced'),
        findsNothing,
        reason: 'the old copy asked for a server the user cannot name',
      );
    });
  });

  group('while a scan is running', () {
    testWidgets('the launch buttons are held and the wait is named', (
      tester,
    ) async {
      final gate = Completer<SyncplayEndpoint?>();
      await pump(
        tester,
        resolveEndpoint: ({SyncplayEndpoint? preferred}) => gate.future,
      );

      await tester.ensureVisible(find.byKey(const Key('connect-start-new')));
      await tester.tap(find.byKey(const Key('connect-start-new')));
      await tester.pump();

      expect(find.text('Finding a server…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('connect-start-new')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('connect-join')))
            .onPressed,
        isNull,
      );

      gate.complete(_default);
      await tester.pumpAndSettle();
      expect(connected, isNotNull);
    });
  });

  group('joining a code', () {
    testWidgets('a share code endpoint is used as written', (tester) async {
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);

      await tester.enterText(
        find.byKey(const Key('connect-code')),
        'sleepy-otter-counts-cozy-stars@cozy.example.net:9000',
      );
      await tester.ensureVisible(find.byKey(const Key('connect-join')));
      await tester.tap(find.byKey(const Key('connect-join')));
      await tester.pumpAndSettle();

      expect(resolver.calls, 0);
      expect(connected!.server, 'cozy.example.net');
      expect(connected!.port, 9000);
    });

    testWidgets('a bare code goes to the default endpoint, not a scan', (
      tester,
    ) async {
      // A bare code is the host saying "the default public endpoint". If the
      // joiner resolved their own instead, two friends could sit in the same
      // room name on different servers.
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);

      await tester.enterText(
        find.byKey(const Key('connect-code')),
        'sleepy-owl-13',
      );
      await tester.ensureVisible(find.byKey(const Key('connect-join')));
      await tester.tap(find.byKey(const Key('connect-join')));
      await tester.pumpAndSettle();

      expect(resolver.calls, 0);
      expect(connected!.server, _default.host);
      expect(connected!.port, _default.port);
    });
  });

  group('rejoining a saved room', () {
    SavedProfile profile(SyncplayEndpoint endpoint) => SavedProfile(
      id: 1,
      name: 'happy-otter-99',
      server: endpoint.host,
      port: endpoint.port,
      room: 'happy-otter-99',
      username: 'lin',
      password: null,
      lastUsedAt: DateTime(2026, 5, 29),
    );

    testWidgets('re-verifies a public endpoint and follows it if it moved', (
      tester,
    ) async {
      profiles.profiles.add(profile(_default));
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);

      await tester.tap(find.text('happy-otter-99'));
      await tester.pumpAndSettle();

      expect(
        resolver.preferred.single,
        _default,
        reason: 'the room is tried where it was last seen, first',
      );
      expect(connected!.port, _moved.port);
      expect(connected!.room, 'happy-otter-99');
    });

    testWidgets('leaves a self-hosted room exactly where it is', (
      tester,
    ) async {
      profiles.profiles.add(profile(_selfHosted));
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);

      await tester.tap(find.text('happy-otter-99'));
      await tester.pumpAndSettle();

      expect(resolver.calls, 0);
      expect(connected!.server, _selfHosted.host);
      expect(connected!.port, _selfHosted.port);
    });

    testWidgets('does not connect when nothing answers', (tester) async {
      profiles.profiles.add(profile(_default));
      await pump(tester, resolveEndpoint: _FakeResolver(null).resolve);

      await tester.tap(find.text('happy-otter-99'));
      await tester.pumpAndSettle();

      expect(connected, isNull);
      expect(find.text(kNoSyncplayServerMessage), findsOneWidget);
    });
  });

  group('continue watching', () {
    HistoryEntry entry(SyncplayEndpoint endpoint) => HistoryEntry(
      id: 1,
      filePath: 'C:/movies/cats.mkv',
      fileName: 'cats.mkv',
      fileSizeBytes: 10,
      durationMs: 1000,
      lastPositionMs: 500,
      playedAt: DateTime(2026, 5, 29),
      room: 'happy-otter-99',
      username: 'lin',
      server: endpoint.host,
      port: endpoint.port,
    );

    testWidgets('re-verifies a public endpoint before resuming', (
      tester,
    ) async {
      history.recent.add(entry(_default));
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);

      await tester.ensureVisible(find.text('cats.mkv'));
      await tester.tap(find.text('cats.mkv'));
      await tester.pumpAndSettle();

      expect(resolver.preferred.single, _default);
      expect(connected!.port, _moved.port);
      expect(connected!.resumeFilePath, 'C:/movies/cats.mkv');
      expect(connected!.resumePositionMs, 500);
    });

    testWidgets('leaves a self-hosted entry alone', (tester) async {
      history.recent.add(entry(_selfHosted));
      final resolver = _FakeResolver(_moved);
      await pump(tester, resolveEndpoint: resolver.resolve);

      await tester.ensureVisible(find.text('cats.mkv'));
      await tester.tap(find.text('cats.mkv'));
      await tester.pumpAndSettle();

      expect(resolver.calls, 0);
      expect(connected!.server, _selfHosted.host);
    });
  });
}
