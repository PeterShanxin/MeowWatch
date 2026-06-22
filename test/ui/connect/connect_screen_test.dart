import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/data/history_collapse.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/history_mode.dart';
import 'package:meowwatch/core/data/saved_profile.dart';
import 'package:meowwatch/core/data/settings_store.dart';
import 'package:meowwatch/core/data/stores.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/connect/connect_screen.dart';
import 'package:meowwatch/ui/version_badge.dart';

class _FakeProfileStore implements ProfileStore {
  final _ctrl = StreamController<List<SavedProfile>>.broadcast();
  final List<SavedProfile> profiles = [];
  final List<int> deleted = [];
  final List<String> savedUsernames = [];
  int saveUsedCalls = 0;

  void emit() => _ctrl.add(List.unmodifiable(profiles));

  @override
  Stream<List<SavedProfile>> watchProfiles() async* {
    yield List.unmodifiable(profiles);
    yield* _ctrl.stream;
  }

  @override
  Future<void> saveUsed({
    required String name,
    required String server,
    required int port,
    required String room,
    required String username,
    String? password,
  }) async {
    saveUsedCalls++;
    savedUsernames.add(username);
  }

  @override
  Future<void> delete(int id) async {
    deleted.add(id);
    profiles.removeWhere((p) => p.id == id);
    emit();
  }
}

class _FakeSettingsStore implements SettingsStore {
  final Map<String, String> _map = {};

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<void> set(String key, String value) async => _map[key] = value;

  @override
  Future<bool> hasAnySettings() async => _map.isNotEmpty;
}

/// Settings store whose writes block on a caller-controlled gate, to test that
/// the connect screen flushes pending lobby-settings writes before navigating.
class _GatedSettingsStore implements SettingsStore {
  _GatedSettingsStore(this._gate);

  final Future<void> _gate;
  final Map<String, String> map = {};

  @override
  Future<String?> get(String key) async => map[key];

  @override
  Future<void> set(String key, String value) async {
    await _gate;
    map[key] = value;
  }

  @override
  Future<bool> hasAnySettings() async => map.isNotEmpty;
}

class _FakeHistoryStore implements HistoryStore {
  final List<HistoryEntry> recent = [];
  final _ctrl = StreamController<List<HistoryEntry>>.broadcast();

  void emit() => _ctrl.add(List.unmodifiable(recent));

  @override
  Stream<List<HistoryEntry>> watchRecent({
    int limit = 6,
    HistoryMode mode = HistoryMode.everyVideo,
  }) async* {
    // Mirror production: collapse the newest-first backing list per [mode],
    // then take [limit], so the fake honours the same view filter.
    List<HistoryEntry> view() =>
        collapseHistory(recent, mode).take(limit).toList();
    yield view();
    yield* _ctrl.stream.map((_) => view());
  }

  @override
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
    String? room,
    String? username,
  }) async {}

  @override
  Future<void> updatePosition({
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {}

  @override
  Future<void> delete(int id) async {
    recent.removeWhere((e) => e.id == id);
    emit();
  }

  @override
  Future<void> clearAll() async {
    recent.clear();
    emit();
  }
}

void main() {
  late _FakeProfileStore profiles;
  late _FakeHistoryStore history;
  RoomConfig? connected;

  Future<void> pump(
    WidgetTester tester, {
    SettingsStore? settings,
    Future<void> Function(RoomConfig config)? onConnect,
  }) async {
    connected = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: ConnectScreen(
          profiles: profiles,
          history: history,
          settings: settings ?? _FakeSettingsStore(),
          currentTheme: MeowThemeId.cozy,
          onThemeChanged: (_) {},
          onConnect:
              onConnect ??
              (config) async {
                connected = config;
              },
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    profiles = _FakeProfileStore();
    history = _FakeHistoryStore();
    // ConnectScreen embeds a VersionBadge whose silent update check uses
    // process-wide statics; reset so these tests stay order-independent.
    VersionBadge.resetForTest();
  });

  testWidgets('renders a saved profile card', (tester) async {
    // Use a name that won't collide with the enter-code hint placeholder.
    profiles.profiles.add(
      SavedProfile(
        id: 1,
        name: 'happy-otter-99',
        server: 'syncplay.pl',
        port: 8999,
        room: 'happy-otter-99',
        username: 'lin',
        password: null,
        lastUsedAt: DateTime(2026, 5, 29),
      ),
    );
    await pump(tester);
    expect(find.text('happy-otter-99'), findsOneWidget);
  });

  testWidgets('name field clear button appears only while filled', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const Key('connect-name-clear')), findsNothing);

    await tester.enterText(find.byKey(const Key('connect-name')), 'alice');
    await tester.pump();

    final clearButton = find.byKey(const Key('connect-name-clear'));
    expect(clearButton, findsOneWidget);
    expect(tester.widget<IconButton>(clearButton).tooltip, 'Clear name');

    await tester.tap(clearButton);
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('connect-name')))
          .controller!
          .text,
      '',
    );
    expect(find.byKey(const Key('connect-name-clear')), findsNothing);
  });

  testWidgets('Start new room generates a private code and connects', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.ensureVisible(find.byKey(const Key('connect-start-new')));
    await tester.tap(find.byKey(const Key('connect-start-new')));
    await tester.pumpAndSettle(); // let Clipboard.setData + saveUsed resolve
    expect(connected, isNotNull);
    // The room is a short "magic sentence" whose entropy lives in the words:
    // <adj>-<animal>-<verb>-<adj>-<noun>, always within Syncplay's 35-char cap.
    expect(
      connected!.room,
      matches(RegExp(r'^[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+$')),
    );
    expect(connected!.room.length, lessThanOrEqualTo(35));
    // The unguessable code is the room name itself; nothing is sent as a server
    // password (that would be a no-op on the public server and could be
    // rejected elsewhere).
    expect(connected!.password, isNull);
    expect(connected!.username, 'lin');
    expect(profiles.saveUsedCalls, 1);
    expect(profiles.savedUsernames.single, 'lin');
  });

  testWidgets('Enter code joins an old room-only code unchanged (#108)', (
    tester,
  ) async {
    // Backward compatibility: a friend on the old build shares "sleepy-owl-13".
    // It must join that exact room with no password, so old + new clients meet.
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.enterText(
      find.byKey(const Key('connect-code')),
      'sleepy-owl-13',
    );
    await tester.ensureVisible(find.byKey(const Key('connect-join')));
    await tester.tap(find.byKey(const Key('connect-join')));
    await tester.pump();
    expect(connected!.room, 'sleepy-owl-13');
    expect(connected!.password, isNull);
  });

  testWidgets('Enter code joins a folded private code verbatim', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.enterText(
      find.byKey(const Key('connect-code')),
      'sleepy-owl-13-k3pn',
    );
    await tester.ensureVisible(find.byKey(const Key('connect-join')));
    await tester.tap(find.byKey(const Key('connect-join')));
    await tester.pump();
    // The whole code is the room, so a friend lands in the host's exact private
    // room. The secret is not re-sent as a server password.
    expect(connected!.room, 'sleepy-owl-13-k3pn');
    expect(connected!.password, isNull);
  });

  testWidgets(
    'Enter code with @host:port joins that server in one paste (#110)',
    (tester) async {
      // A self-contained share code carries the host's non-default server/port, so
      // the friend joins without touching Advanced.
      await pump(tester);
      await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
      await tester.enterText(
        find.byKey(const Key('connect-code')),
        'sleepy-otter-counts-cozy-stars@cozy.example.net:9000',
      );
      await tester.ensureVisible(find.byKey(const Key('connect-join')));
      await tester.tap(find.byKey(const Key('connect-join')));
      await tester.pump();
      expect(connected!.room, 'sleepy-otter-counts-cozy-stars');
      expect(connected!.server, 'cozy.example.net');
      expect(connected!.port, 9000);
    },
  );

  testWidgets('Enter code rejects a malformed share code with feedback (#110)', (
    tester,
  ) async {
    // A structured-but-broken code must warn, not silently join a garbage room.
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.enterText(
      find.byKey(const Key('connect-code')),
      'sleepy-otter-counts-cozy-stars@cozy.example.net:notaport',
    );
    await tester.ensureVisible(find.byKey(const Key('connect-join')));
    await tester.tap(find.byKey(const Key('connect-join')));
    await tester.pump();
    expect(connected, isNull);
    expect(find.textContaining('looks off'), findsOneWidget);
  });

  testWidgets('share code with a server but no port uses the host default, not '
      'Advanced Port (#110)', (tester) async {
    // A server-bearing code that omits the port (here a bracketed IPv6 host)
    // must dial the Syncplay default 8999 — never the joiner's Advanced Port.
    await pump(tester);
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.tap(find.byKey(const Key('connect-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('connect-advanced-port')),
      '1234',
    );
    await tester.enterText(
      find.byKey(const Key('connect-code')),
      'sleepy-otter-counts-cozy-stars@[2001:db8::1]',
    );
    await tester.ensureVisible(find.byKey(const Key('connect-join')));
    await tester.tap(find.byKey(const Key('connect-join')));
    await tester.pump();
    expect(connected!.server, '2001:db8::1');
    expect(connected!.port, 8999);
  });

  testWidgets('a bare room code still honors the Advanced server/port (#110)', (
    tester,
  ) async {
    // No server in the code → fall back to whatever the joiner typed in Advanced.
    await pump(tester);
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.tap(find.byKey(const Key('connect-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('connect-advanced-server')),
      'my.lan',
    );
    await tester.enterText(
      find.byKey(const Key('connect-advanced-port')),
      '1234',
    );
    await tester.enterText(
      find.byKey(const Key('connect-code')),
      'happy-cat-11',
    );
    await tester.ensureVisible(find.byKey(const Key('connect-join')));
    await tester.tap(find.byKey(const Key('connect-join')));
    await tester.pump();
    expect(connected!.room, 'happy-cat-11');
    expect(connected!.server, 'my.lan');
    expect(connected!.port, 1234);
  });

  testWidgets('Advanced password is sent without mutating the typed room', (
    tester,
  ) async {
    // Regression for the private/self-hosted server case: typing a plain room
    // plus an Advanced (server) password must join that exact room and send the
    // password in the handshake — never fold the password into the room name.
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.enterText(find.byKey(const Key('connect-code')), 'movienight');
    await tester.tap(find.byKey(const Key('connect-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('connect-advanced-password')),
      'secret',
    );
    await tester.ensureVisible(find.byKey(const Key('connect-join')));
    await tester.tap(find.byKey(const Key('connect-join')));
    await tester.pump();
    expect(connected!.room, 'movienight');
    expect(connected!.password, 'secret');
  });

  testWidgets('Advanced password is labelled as a server password (#117)', (
    tester,
  ) async {
    // The field wires to the Syncplay handshake as the server password, not a
    // per-room password — the label must say so, and not the old misleading
    // "Room password" that implied it locked a public room.
    await pump(tester);
    await tester.tap(find.byKey(const Key('connect-advanced')));
    await tester.pumpAndSettle();
    expect(
      find.text('Server password — advanced / self-hosted only'),
      findsOneWidget,
    );
    expect(find.textContaining('Room password'), findsNothing);
  });

  testWidgets('Advanced fields reset individually when changed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester);
    await tester.tap(find.byKey(const Key('connect-advanced')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('connect-advanced-server-reset')),
      findsNothing,
    );
    expect(find.byKey(const Key('connect-advanced-port-reset')), findsNothing);
    expect(
      find.byKey(const Key('connect-advanced-password-reset')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('connect-advanced-server')),
      'my.lan',
    );
    await tester.enterText(
      find.byKey(const Key('connect-advanced-port')),
      '1234',
    );
    await tester.enterText(
      find.byKey(const Key('connect-advanced-password')),
      'secret',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('connect-advanced-server-reset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('connect-advanced-port-reset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('connect-advanced-password-reset')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('connect-advanced-server-reset')),
          )
          .tooltip,
      'Reset to default',
    );

    await tester.tap(find.byKey(const Key('connect-advanced-server-reset')));
    await tester.tap(find.byKey(const Key('connect-advanced-port-reset')));
    await tester.tap(find.byKey(const Key('connect-advanced-password-reset')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('connect-advanced-server')))
          .controller!
          .text,
      'syncplay.pl',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('connect-advanced-port')))
          .controller!
          .text,
      '8999',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('connect-advanced-password')))
          .controller!
          .text,
      '',
    );
  });

  testWidgets('Advanced edit confirms after the field loses focus', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('connect-advanced')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('connect-advanced-server')),
      'my.lan',
    );
    await tester.tap(find.byKey(const Key('connect-name')));
    await tester.pump();

    expect(find.text('Advanced setting updated.'), findsOneWidget);
  });

  testWidgets('settings gear opens the lobby settings popover', (tester) async {
    await pump(tester);
    // Theme is no longer inline on the form — it moved into the gear.
    expect(find.text('Theme'), findsNothing);
    expect(find.byKey(const Key('lobby-settings-gear')), findsOneWidget);
    expect(find.text('Diagnostic logging'), findsNothing);

    await tester.tap(find.byKey(const Key('lobby-settings-gear')));
    await tester.pumpAndSettle();

    // The settings-only popover: theme + sounds + logging, no room rows.
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Diagnostic logging'), findsOneWidget);
    expect(find.byKey(const Key('player-menu-leave')), findsNothing);
  });

  testWidgets('Start waits for a pending lobby-settings write before connecting', (
    tester,
  ) async {
    // A level the user just picked in the lobby gear must reach the room. Hold
    // the settings write open, change the level, hit Start — the room must not
    // be entered until the write lands, or HomeScreen would read the old value
    // (PR #131 review).
    final gate = Completer<void>();
    final settings = _GatedSettingsStore(gate.future);
    await pump(tester, settings: settings);
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.byKey(const Key('lobby-settings-gear')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('player-menu-log-neat')));
    await tester.tap(find.byKey(const Key('player-menu-log-neat')));
    await tester.pumpAndSettle();
    // Close the gear so the Start button underneath is tappable.
    await tester.tap(find.byKey(const Key('lobby-settings-gear')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.ensureVisible(find.byKey(const Key('connect-start-new')));
    await tester.tap(find.byKey(const Key('connect-start-new')));
    await tester.pump();

    // The write is still gated, so connect must not have fired yet.
    expect(connected, isNull);

    gate.complete();
    await tester.pumpAndSettle();

    // Now the room is entered, and the freshly-picked level was persisted first.
    expect(connected, isNotNull);
    expect(settings.map[kLogLevelSettingKey], 'neat');
  });

  testWidgets('delete icon removes the profile', (tester) async {
    profiles.profiles.add(
      SavedProfile(
        id: 7,
        name: 'r',
        server: 's',
        port: 1,
        room: 'r',
        username: 'u',
        password: null,
        lastUsedAt: DateTime(2026),
      ),
    );
    await pump(tester);
    await tester.ensureVisible(find.byKey(const Key('connect-delete-7')));
    await tester.tap(find.byKey(const Key('connect-delete-7')));
    await tester.pump();
    expect(profiles.deleted, [7]);
  });

  testWidgets('saved room shows an alternate current-name action', (
    tester,
  ) async {
    profiles.profiles.add(
      SavedProfile(
        id: 7,
        name: 'cozy-fox-42',
        server: 'syncplay.pl',
        port: 8999,
        room: 'cozy-fox-42',
        username: 'meowPEOW',
        password: null,
        lastUsedAt: DateTime(2026),
      ),
    );
    await pump(tester);

    await tester.enterText(find.byKey(const Key('connect-name')), 'alice');
    await tester.pump();

    expect(
      find.byKey(const Key('connect-profile-use-current-7')),
      findsOneWidget,
    );
    expect(find.text('Join as alice this time'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connect-profile-use-current-7')));
    await tester.pumpAndSettle();

    expect(connected!.room, 'cozy-fox-42');
    expect(connected!.username, 'alice');
    expect(profiles.savedUsernames.single, 'meowPEOW');
  });

  testWidgets(
    'saved room tap keeps the typed-name option stable while entering',
    (tester) async {
      final gate = Completer<void>();
      profiles.profiles.add(
        SavedProfile(
          id: 7,
          name: 'cozy-fox-42',
          server: 'syncplay.pl',
          port: 8999,
          room: 'cozy-fox-42',
          username: 'meowPEOW',
          password: null,
          lastUsedAt: DateTime(2026),
        ),
      );
      await pump(
        tester,
        onConnect: (config) async {
          connected = config;
          await gate.future;
        },
      );

      await tester.enterText(find.byKey(const Key('connect-name')), 'alice');
      await tester.pump();
      final action = find.byKey(const Key('connect-profile-use-current-7'));
      expect(action, findsOneWidget);

      await tester.tap(find.text('cozy-fox-42'));
      await tester.pump();

      expect(connected!.username, 'meowPEOW');
      expect(action, findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('connect-name')))
            .controller!
            .text,
        'alice',
      );

      gate.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('saved room keeps the typed name after returning', (
    tester,
  ) async {
    final gate = Completer<void>();
    profiles.profiles.add(
      SavedProfile(
        id: 7,
        name: 'cozy-fox-42',
        server: 'syncplay.pl',
        port: 8999,
        room: 'cozy-fox-42',
        username: 'meowPEOW',
        password: null,
        lastUsedAt: DateTime(2026),
      ),
    );
    await pump(
      tester,
      onConnect: (config) async {
        connected = config;
        await gate.future;
      },
    );

    await tester.enterText(find.byKey(const Key('connect-name')), 'alice');
    await tester.pump();
    await tester.tap(find.text('cozy-fox-42'));
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(connected!.username, 'meowPEOW');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('connect-name')))
          .controller!
          .text,
      'alice',
    );
  });

  testWidgets('saved room current-name action expands the card smoothly', (
    tester,
  ) async {
    profiles.profiles.add(
      SavedProfile(
        id: 7,
        name: 'cozy-fox-42',
        server: 'syncplay.pl',
        port: 8999,
        room: 'cozy-fox-42',
        username: 'meowPEOW',
        password: null,
        lastUsedAt: DateTime(2026),
      ),
    );
    await pump(tester);
    final card = find.byType(Card).first;
    final before = tester.getSize(card);

    await tester.enterText(find.byKey(const Key('connect-name')), 'alice');
    await tester.pump();
    expect(
      find.byKey(const Key('connect-profile-use-current-7')),
      findsOneWidget,
    );
    expect(find.byType(AnimatedSize), findsWidgets);

    await tester.pump(const Duration(milliseconds: 100));
    final during = tester.getSize(card);
    await tester.pumpAndSettle();
    final after = tester.getSize(card);

    expect(after.height, greaterThan(before.height));
    expect(during.height, inInclusiveRange(before.height, after.height));
  });

  HistoryEntry historyEntry(int id, String name) => HistoryEntry(
    id: id,
    filePath: '/$name.mkv',
    fileName: '$name.mkv',
    fileSizeBytes: 1,
    durationMs: 600000,
    lastPositionMs: 120000,
    playedAt: DateTime(2026, 5, 29),
  );

  testWidgets('continue-watching row shows progress and can be deleted', (
    tester,
  ) async {
    history.recent
      ..add(historyEntry(1, 'ep1'))
      ..add(historyEntry(2, 'ep2'));
    await pump(tester);

    // Rich subtitle: 2:00 / 10:00 · 20% · ...
    expect(find.textContaining('2:00 / 10:00 · 20%'), findsNWidgets(2));

    await tester.ensureVisible(find.byKey(const Key('continue-delete-1')));
    await tester.tap(find.byKey(const Key('continue-delete-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('continue-1')), findsNothing);
    expect(find.byKey(const Key('continue-2')), findsOneWidget);
  });

  HistoryEntry historyEntryAs(int id, String name, String username) =>
      HistoryEntry(
        id: id,
        filePath: '/$name.mkv',
        fileName: '$name.mkv',
        fileSizeBytes: 1,
        durationMs: 600000,
        lastPositionMs: 120000,
        playedAt: DateTime(2026, 5, 29),
        room: 'cozy-fox-42',
        username: username,
      );

  testWidgets(
    'continue-watching resumes with the saved username when name is blank',
    (tester) async {
      // #40: resuming with an empty name field must reuse the name the file was
      // watched as, not silently fall back to the "meow" default.
      history.recent.add(historyEntryAs(1, 'ep1', 'meowPEOW'));
      await pump(tester);

      await tester.ensureVisible(find.byKey(const Key('continue-1')));
      await tester.tap(find.byKey(const Key('continue-1')));
      await tester.pumpAndSettle();

      expect(connected!.username, 'meowPEOW');
    },
  );

  testWidgets(
    'continue-watching keeps saved username on the main card (#138)',
    (tester) async {
      history.recent.add(historyEntryAs(1, 'ep1', 'meowPEOW'));
      await pump(tester);

      await tester.enterText(find.byKey(const Key('connect-name')), 'alice');
      await tester.ensureVisible(find.byKey(const Key('continue-1')));
      await tester.tap(find.byKey(const Key('continue-1')));
      await tester.pumpAndSettle();

      expect(connected!.username, 'meowPEOW');
    },
  );

  testWidgets('continue-watching offers the freshly typed username (#138)', (
    tester,
  ) async {
    history.recent.add(historyEntryAs(1, 'ep1', 'meowPEOW'));
    await pump(tester);

    await tester.enterText(find.byKey(const Key('connect-name')), 'alice');
    await tester.pump();
    expect(find.text('Join as alice this time'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('continue-use-current-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-use-current-1')));
    await tester.pumpAndSettle();

    expect(connected!.username, 'alice');
    expect(connected!.room, 'cozy-fox-42');
    expect(profiles.savedUsernames.single, 'meowPEOW');
  });

  HistoryEntry historyEntryInRoom(int id, String name, String room) =>
      HistoryEntry(
        id: id,
        filePath: '/$name.mkv',
        fileName: '$name.mkv',
        fileSizeBytes: 1,
        durationMs: 600000,
        lastPositionMs: 120000,
        playedAt: DateTime(2026, 5, 29),
        room: room,
      );

  testWidgets('Continue watching collapses to latest per room by default', (
    tester,
  ) async {
    // Two files in the same room (newest-first: ep2 then ep1). The default
    // latestPerRoom mode hides the older same-room entry.
    history.recent
      ..add(historyEntryInRoom(2, 'ep2', 'cozy'))
      ..add(historyEntryInRoom(1, 'ep1', 'cozy'));
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('ep2.mkv'), findsOneWidget);
    expect(find.text('ep1.mkv'), findsNothing);
  });

  testWidgets('Clear all empties continue-watching', (tester) async {
    history.recent
      ..add(historyEntry(1, 'ep1'))
      ..add(historyEntry(2, 'ep2'));
    await pump(tester);

    await tester.ensureVisible(find.byKey(const Key('continue-clear-all')));
    await tester.tap(find.byKey(const Key('continue-clear-all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('continue-1')), findsNothing);
    expect(find.byKey(const Key('continue-2')), findsNothing);
    expect(find.text('Continue watching'), findsNothing);
  });
}
