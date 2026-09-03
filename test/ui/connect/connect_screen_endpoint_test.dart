import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/saved_profile.dart';
import 'package:meowwatch/core/data/settings_store.dart';
import 'package:meowwatch/core/sync/syncplay_endpoints.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/connect/connect_screen.dart';
import 'package:meowwatch/ui/version_badge.dart';

import '../../support/fakes.dart';

/// #234 — which launches walk public candidates and which are pinned.
///
/// The lobby does not probe. It names a policy; the real join in
/// `MeowWatchApp` walks or pins. Two peers can only meet if "where is this
/// room" is the same on both machines.
const _default = SyncplayEndpoint(host: 'syncplay.pl', port: 8995);
const _moved = SyncplayEndpoint(host: 'syncplay.pl', port: 8997);
const _selfHosted = SyncplayEndpoint(host: 'cozy.example.net', port: 8999);

void main() {
  late FakeProfileStore profiles;
  late FakeHistoryStore history;
  RoomConfig? connected;
  Completer<String?>? joinGate;

  Future<void> pump(WidgetTester tester, {SettingsStore? settings}) async {
    connected = null;
    joinGate = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: ConnectScreen(
          profiles: profiles,
          history: history,
          settings: settings ?? FakeSettingsStore(),
          currentTheme: MeowThemeId.cozy,
          onThemeChanged: (_) {},
          onConnect: (config) async {
            connected = config;
            final gate = joinGate;
            if (gate != null) return gate.future;
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
    testWidgets('default Start walks public candidates', (tester) async {
      await pump(tester);

      await tapStart(tester);

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.discover);
      expect(connected!.copyShareCode, isTrue);
      expect(connected!.server, _default.host);
      expect(connected!.port, _default.port);
    });

    testWidgets('never walks over an Advanced server', (tester) async {
      await pump(tester);
      await setAdvanced(tester, server: 'my.lan', port: '1234');

      await tapStart(tester);

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(connected!.copyShareCode, isTrue);
      expect(connected!.server, 'my.lan');
      expect(connected!.port, 1234);
    });

    testWidgets('never walks over an Advanced port alone', (tester) async {
      await pump(tester);
      await setAdvanced(tester, port: '8999');

      await tapStart(tester);

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(connected!.server, 'syncplay.pl');
      expect(connected!.port, 8999);
    });
  });

  group('while a discoverable join is running', () {
    testWidgets('the launch buttons are held and the wait is named', (
      tester,
    ) async {
      await pump(tester);
      joinGate = Completer<String?>();

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

      joinGate!.complete(null);
      await tester.pumpAndSettle();
      expect(connected, isNotNull);
    });
  });

  group('joining a code', () {
    testWidgets('a share code endpoint is pinned as written', (tester) async {
      await pump(tester);

      await tester.enterText(
        find.byKey(const Key('connect-code')),
        'sleepy-otter-counts-cozy-stars@cozy.example.net:9000',
      );
      await tester.ensureVisible(find.byKey(const Key('connect-join')));
      await tester.tap(find.byKey(const Key('connect-join')));
      await tester.pumpAndSettle();

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(connected!.server, 'cozy.example.net');
      expect(connected!.port, 9000);
    });

    testWidgets('a bare code is a legacy pin, not a scan', (tester) async {
      await pump(tester);

      await tester.enterText(
        find.byKey(const Key('connect-code')),
        'sleepy-owl-13',
      );
      await tester.ensureVisible(find.byKey(const Key('connect-join')));
      await tester.tap(find.byKey(const Key('connect-join')));
      await tester.pumpAndSettle();

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(connected!.server, _default.host);
      expect(connected!.port, _default.port);
    });

    testWidgets(
      'a bare code ignores a remembered winner and Advanced leftover',
      (tester) async {
        final settings = FakeSettingsStore();
        await settings.set(kSyncplayEndpointSettingKey, 'syncplay.pl:8999');
        await pump(tester, settings: settings);
        await setAdvanced(tester, server: 'syncplay.pl', port: '8999');

        await tester.enterText(find.byKey(const Key('connect-code')), 'mw272bare');
        await tester.ensureVisible(find.byKey(const Key('connect-join')));
        await tester.tap(find.byKey(const Key('connect-join')));
        await tester.pumpAndSettle();

        expect(connected!.room, 'mw272bare');
        expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
        expect(connected!.server, _default.host);
        expect(connected!.port, _default.port);
      },
    );
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

    testWidgets('a public saved room may walk from that address', (
      tester,
    ) async {
      profiles.profiles.add(profile(_default));
      await pump(tester);

      await tester.tap(find.text('happy-otter-99'));
      await tester.pumpAndSettle();

      expect(
        connected!.endpointPolicy,
        SyncplayEndpointPolicy.discoverFromRoom,
      );
      expect(connected!.server, _default.host);
      expect(connected!.port, _default.port);
      expect(connected!.room, 'happy-otter-99');
    });

    testWidgets('a pinned public saved room stays exact', (tester) async {
      profiles.profiles.add(profile(_default).copyWith(endpointPinned: true));
      await pump(tester);

      await tester.tap(find.text('happy-otter-99'));
      await tester.pumpAndSettle();

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(connected!.server, _default.host);
      expect(connected!.port, _default.port);
    });

    testWidgets('leaves a self-hosted room exactly where it is', (
      tester,
    ) async {
      profiles.profiles.add(
        profile(_selfHosted).copyWith(endpointPinned: true),
      );
      await pump(tester);

      await tester.tap(find.text('happy-otter-99'));
      await tester.pumpAndSettle();

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(connected!.server, _selfHosted.host);
      expect(connected!.port, _selfHosted.port);
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

    testWidgets('a public entry may walk from where it was last seen', (
      tester,
    ) async {
      history.recent.add(entry(_default));
      await pump(tester);

      await tester.ensureVisible(find.text('cats.mkv'));
      await tester.tap(find.text('cats.mkv'));
      await tester.pumpAndSettle();

      expect(
        connected!.endpointPolicy,
        SyncplayEndpointPolicy.discoverFromRoom,
      );
      expect(connected!.port, _default.port);
      expect(connected!.resumeFilePath, 'C:/movies/cats.mkv');
      expect(connected!.resumePositionMs, 500);
    });

    testWidgets('a pinned public entry stays exact', (tester) async {
      history.recent.add(entry(_default).copyWith(endpointPinned: true));
      await pump(tester);

      await tester.ensureVisible(find.text('cats.mkv'));
      await tester.tap(find.text('cats.mkv'));
      await tester.pumpAndSettle();

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(connected!.port, _default.port);
    });

    testWidgets('leaves a self-hosted entry alone', (tester) async {
      history.recent.add(entry(_selfHosted).copyWith(endpointPinned: true));
      await pump(tester);

      await tester.ensureVisible(find.text('cats.mkv'));
      await tester.tap(find.text('cats.mkv'));
      await tester.pumpAndSettle();

      expect(connected!.endpointPolicy, SyncplayEndpointPolicy.pinned);
      expect(connected!.server, _selfHosted.host);
    });

    testWidgets('a moved public entry is still the preferred start', (
      tester,
    ) async {
      history.recent.add(entry(_moved));
      await pump(tester);

      await tester.ensureVisible(find.text('cats.mkv'));
      await tester.tap(find.text('cats.mkv'));
      await tester.pumpAndSettle();

      expect(
        connected!.endpointPolicy,
        SyncplayEndpointPolicy.discoverFromRoom,
      );
      expect(connected!.port, _moved.port);
    });
  });
}
