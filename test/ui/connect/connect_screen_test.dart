import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/saved_profile.dart';
import 'package:meowwatch/core/data/stores.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/connect/connect_screen.dart';

class _FakeProfileStore implements ProfileStore {
  final _ctrl = StreamController<List<SavedProfile>>.broadcast();
  final List<SavedProfile> profiles = [];
  final List<int> deleted = [];
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
  }

  @override
  Future<void> delete(int id) async {
    deleted.add(id);
    profiles.removeWhere((p) => p.id == id);
    emit();
  }
}

class _FakeHistoryStore implements HistoryStore {
  final List<HistoryEntry> recent = [];
  final _ctrl = StreamController<List<HistoryEntry>>.broadcast();

  void emit() => _ctrl.add(List.unmodifiable(recent));

  @override
  Stream<List<HistoryEntry>> watchRecent({int limit = 6}) async* {
    yield List.unmodifiable(recent);
    yield* _ctrl.stream;
  }

  @override
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
  }) async {}

  @override
  Future<void> updatePosition({
    required String filePath,
    required int positionMs,
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

  Future<void> pump(WidgetTester tester) async {
    connected = null;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: ConnectScreen(
        profiles: profiles,
        history: history,
        currentTheme: MeowThemeId.cozy,
        onThemeChanged: (_) {},
        onConnect: (config) async => connected = config,
      ),
    ));
    await tester.pump();
  }

  setUp(() {
    profiles = _FakeProfileStore();
    history = _FakeHistoryStore();
  });

  testWidgets('renders a saved profile card', (tester) async {
    // Use a name that won't collide with the enter-code hint placeholder.
    profiles.profiles.add(SavedProfile(
      id: 1,
      name: 'happy-otter-99',
      server: 'syncplay.pl',
      port: 8999,
      room: 'happy-otter-99',
      username: 'lin',
      password: null,
      lastUsedAt: DateTime(2026, 5, 29),
    ));
    await pump(tester);
    expect(find.text('happy-otter-99'), findsOneWidget);
  });

  testWidgets('Start new room generates a code and connects', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.ensureVisible(find.byKey(const Key('connect-start-new')));
    await tester.tap(find.byKey(const Key('connect-start-new')));
    await tester.pumpAndSettle(); // let Clipboard.setData + saveUsed resolve
    expect(connected, isNotNull);
    expect(connected!.room, matches(RegExp(r'^[a-z]+-[a-z]+-\d{2}$')));
    expect(connected!.username, 'lin');
    expect(profiles.saveUsedCalls, 1);
  });

  testWidgets('Enter code joins the typed room', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.enterText(
        find.byKey(const Key('connect-code')), 'sleepy-owl-13');
    await tester.ensureVisible(find.byKey(const Key('connect-join')));
    await tester.tap(find.byKey(const Key('connect-join')));
    await tester.pump();
    expect(connected!.room, 'sleepy-owl-13');
  });

  testWidgets('delete icon removes the profile', (tester) async {
    profiles.profiles.add(SavedProfile(
      id: 7,
      name: 'r',
      server: 's',
      port: 1,
      room: 'r',
      username: 'u',
      password: null,
      lastUsedAt: DateTime(2026),
    ));
    await pump(tester);
    await tester.ensureVisible(find.byKey(const Key('connect-delete-7')));
    await tester.tap(find.byKey(const Key('connect-delete-7')));
    await tester.pump();
    expect(profiles.deleted, [7]);
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

  testWidgets('continue-watching row shows progress and can be deleted',
      (tester) async {
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
