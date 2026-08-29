# Phase 4: Connect Flow + Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary dev connect bar with a real Connect screen: saved profile cards, one-click "Start new room" (auto room code), "Enter code from friend", a "Continue watching" list, and an Advanced section — all backed by a local SQLite database (drift).

**Architecture:** A small data layer (`lib/core/data/`) defines two immutable domain models (`SavedProfile`, `HistoryEntry`) and two abstract stores (`ProfileStore`, `HistoryStore`). A drift `AppDatabase` provides the concrete SQLite-backed implementations. The UI gains a `ConnectScreen` (home) that talks only to the abstract stores and, on connect, navigates to the existing `HomeScreen` — now driven by an immutable `RoomConfig` instead of the dev bar. `HomeScreen` records watch history and gets a small Leave button to return to the Connect screen.

**Tech Stack:** Flutter desktop, `drift` (SQLite ORM) + `sqlite3_flutter_libs` + `path_provider`, `build_runner` for codegen. Tests: `flutter_test` + in-memory drift (`NativeDatabase.memory()`).

**Locked design decisions (from the user):**
1. **Passwords:** optional, stored **plaintext** in the local DB (not an OS keystore). User's explicit choice.
2. **History:** include now — record watched files + show a "Continue watching" section that resumes position.
3. **Leave room:** a small "Leave" button on the watch screen returns to Connect.
4. **Saving rooms:** auto-save a profile on every connect; profiles are deletable from the list.

**Conventions for every task:**
- Flutter binary (NOT on PATH): `FLUTTER=%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat`
- Keep `$FLUTTER analyze` at "No issues found!" before each commit.
- Conventional-commit messages (`feat:`, `fix:`, `chore:`, `test:`).
- Immutable state objects (`@immutable` + `copyWith`), small focused files.

---

## File Structure

**New files:**
- `lib/core/connect/room_code.dart` — pure room-code generator (`generateRoomCode`).
- `lib/core/connect/room_config.dart` — immutable `RoomConfig` passed Connect → Home.
- `lib/core/data/saved_profile.dart` — immutable `SavedProfile` domain model.
- `lib/core/data/history_entry.dart` — immutable `HistoryEntry` domain model.
- `lib/core/data/stores.dart` — abstract `ProfileStore` + `HistoryStore` interfaces.
- `lib/core/data/app_database.dart` — drift tables + `AppDatabase` (+ generated `app_database.g.dart`).
- `lib/core/data/drift_stores.dart` — `DriftProfileStore`, `DriftHistoryStore` (map rows ↔ models).
- `lib/ui/connect/connect_screen.dart` — the Connect screen widget.
- Tests: `test/core/connect/room_code_test.dart`, `test/core/connect/room_config_test.dart`, `test/core/data/saved_profile_test.dart`, `test/core/data/history_entry_test.dart`, `test/core/data/drift_profile_store_test.dart`, `test/core/data/drift_history_store_test.dart`, `test/ui/connect/connect_screen_test.dart`.

**Modified files:**
- `lib/ui/home_screen.dart` — config-driven, auto-connect, Leave button, history recording; remove dev bar.
- `lib/app.dart` — accept stores, show `ConnectScreen`, wire connect → navigate to `HomeScreen`.
- `lib/main.dart` — open the database, construct stores, pass to `MeowWatchApp`.
- `pubspec.yaml` — add drift + tooling deps.

**Removed files:**
- `lib/ui/dev_connect_bar.dart` — superseded by `ConnectScreen`.

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add runtime + dev dependencies**

Run (uses pub to resolve compatible versions for Dart 3.12):

```bash
FLUTTER=%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat
$FLUTTER pub add drift sqlite3_flutter_libs path_provider
$FLUTTER pub add dev:drift_dev dev:build_runner
```

- [ ] **Step 2: Verify pubspec + fetch**

Run: `$FLUTTER pub get`
Expected: resolves with no errors; `pubspec.yaml` now lists `drift`, `sqlite3_flutter_libs`, `path_provider` under dependencies and `drift_dev`, `build_runner` under dev_dependencies.

- [ ] **Step 3: Sanity analyze**

Run: `$FLUTTER analyze`
Expected: "No issues found!" (new deps unused yet — that's fine).

- [ ] **Step 4: Commit**

```bash
git -C "D:/Repos/MeowWatch" add pubspec.yaml pubspec.lock
git -C "D:/Repos/MeowWatch" commit -m "chore: add drift, sqlite3, path_provider for phase 4 storage"
```

---

## Task 2: Room-code generator

**Files:**
- Create: `lib/core/connect/room_code.dart`
- Test: `test/core/connect/room_code_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/connect/room_code_test.dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_code.dart';

void main() {
  test('produces an adjective-animal-number code', () {
    final code = generateRoomCode(Random(7));
    expect(code, matches(RegExp(r'^[a-z]+-[a-z]+-\d{2}$')));
  });

  test('is deterministic for a fixed seed', () {
    expect(generateRoomCode(Random(42)), generateRoomCode(Random(42)));
  });

  test('number is always two digits (10..99)', () {
    for (var seed = 0; seed < 50; seed++) {
      final number = int.parse(generateRoomCode(Random(seed)).split('-').last);
      expect(number, inInclusiveRange(10, 99));
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/core/connect/room_code_test.dart`
Expected: FAIL — `room_code.dart` / `generateRoomCode` not found.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/connect/room_code.dart
import 'dart:math';

const List<String> _adjectives = <String>[
  'cozy', 'sleepy', 'fuzzy', 'happy', 'silly', 'mellow', 'sunny', 'snug',
  'witty', 'jolly', 'breezy', 'plucky', 'dreamy', 'peppy', 'swift', 'gentle',
];

const List<String> _animals = <String>[
  'fox', 'cat', 'owl', 'panda', 'otter', 'koala', 'lynx', 'hare',
  'wolf', 'seal', 'crow', 'moth', 'newt', 'toad', 'wren', 'yak',
];

/// Generates a friendly room code like `cozy-fox-42`.
///
/// Pass a seeded [Random] in tests for deterministic output.
String generateRoomCode([Random? random]) {
  final r = random ?? Random();
  final adjective = _adjectives[r.nextInt(_adjectives.length)];
  final animal = _animals[r.nextInt(_animals.length)];
  final number = r.nextInt(90) + 10; // 10..99
  return '$adjective-$animal-$number';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/core/connect/room_code_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/core/connect/room_code.dart test/core/connect/room_code_test.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add friendly room-code generator"
```

---

## Task 3: RoomConfig model

**Files:**
- Create: `lib/core/connect/room_config.dart`
- Test: `test/core/connect/room_config_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/connect/room_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';

void main() {
  const base = RoomConfig(
    server: 'syncplay.pl',
    port: 8999,
    room: 'cozy-fox-42',
    username: 'lin',
  );

  test('value equality', () {
    expect(
      base,
      const RoomConfig(
        server: 'syncplay.pl',
        port: 8999,
        room: 'cozy-fox-42',
        username: 'lin',
      ),
    );
  });

  test('defaults: no password, no resume', () {
    expect(base.password, isNull);
    expect(base.resumeFilePath, isNull);
    expect(base.resumePositionMs, 0);
  });

  test('copyWith overrides only named fields', () {
    final withResume =
        base.copyWith(resumeFilePath: 'D:/v.mkv', resumePositionMs: 5000);
    expect(withResume.resumeFilePath, 'D:/v.mkv');
    expect(withResume.resumePositionMs, 5000);
    expect(withResume.room, base.room);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/core/connect/room_config_test.dart`
Expected: FAIL — `room_config.dart` not found.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/connect/room_config.dart
import 'package:flutter/foundation.dart';

/// Everything the watch screen needs to join a room and optionally resume a
/// previously-watched file. Built by [ConnectScreen], consumed by HomeScreen.
@immutable
class RoomConfig {
  const RoomConfig({
    required this.server,
    required this.port,
    required this.room,
    required this.username,
    this.password,
    this.resumeFilePath,
    this.resumePositionMs = 0,
  });

  final String server;
  final int port;
  final String room;
  final String username;
  final String? password;

  /// If set, the watch screen loads this file and seeks to [resumePositionMs].
  final String? resumeFilePath;
  final int resumePositionMs;

  RoomConfig copyWith({
    String? server,
    int? port,
    String? room,
    String? username,
    String? password,
    String? resumeFilePath,
    int? resumePositionMs,
  }) {
    return RoomConfig(
      server: server ?? this.server,
      port: port ?? this.port,
      room: room ?? this.room,
      username: username ?? this.username,
      password: password ?? this.password,
      resumeFilePath: resumeFilePath ?? this.resumeFilePath,
      resumePositionMs: resumePositionMs ?? this.resumePositionMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoomConfig &&
      other.server == server &&
      other.port == port &&
      other.room == room &&
      other.username == username &&
      other.password == password &&
      other.resumeFilePath == resumeFilePath &&
      other.resumePositionMs == resumePositionMs;

  @override
  int get hashCode => Object.hash(server, port, room, username, password,
      resumeFilePath, resumePositionMs);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/core/connect/room_config_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/core/connect/room_config.dart test/core/connect/room_config_test.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add RoomConfig connect→watch payload"
```

---

## Task 4: SavedProfile model

**Files:**
- Create: `lib/core/data/saved_profile.dart`
- Test: `test/core/data/saved_profile_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/data/saved_profile_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/saved_profile.dart';

void main() {
  final used = DateTime(2026, 5, 29, 13);
  final base = SavedProfile(
    id: 1,
    name: 'cozy-fox-42',
    server: 'syncplay.pl',
    port: 8999,
    room: 'cozy-fox-42',
    username: 'lin',
    password: null,
    lastUsedAt: used,
  );

  test('value equality', () {
    expect(
      base,
      SavedProfile(
        id: 1,
        name: 'cozy-fox-42',
        server: 'syncplay.pl',
        port: 8999,
        room: 'cozy-fox-42',
        username: 'lin',
        password: null,
        lastUsedAt: used,
      ),
    );
  });

  test('copyWith updates lastUsedAt', () {
    final later = DateTime(2026, 6, 1);
    expect(base.copyWith(lastUsedAt: later).lastUsedAt, later);
    expect(base.copyWith(lastUsedAt: later).room, base.room);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/core/data/saved_profile_test.dart`
Expected: FAIL — `saved_profile.dart` not found.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/data/saved_profile.dart
import 'package:flutter/foundation.dart';

/// A connection the user has joined before. Auto-saved on every connect and
/// shown as a card on the Connect screen.
@immutable
class SavedProfile {
  const SavedProfile({
    required this.id,
    required this.name,
    required this.server,
    required this.port,
    required this.room,
    required this.username,
    required this.password,
    required this.lastUsedAt,
  });

  final int id;
  final String name;
  final String server;
  final int port;
  final String room;
  final String username;
  final String? password;
  final DateTime? lastUsedAt;

  SavedProfile copyWith({
    int? id,
    String? name,
    String? server,
    int? port,
    String? room,
    String? username,
    String? password,
    DateTime? lastUsedAt,
  }) {
    return SavedProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      server: server ?? this.server,
      port: port ?? this.port,
      room: room ?? this.room,
      username: username ?? this.username,
      password: password ?? this.password,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SavedProfile &&
      other.id == id &&
      other.name == name &&
      other.server == server &&
      other.port == port &&
      other.room == room &&
      other.username == username &&
      other.password == password &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode =>
      Object.hash(id, name, server, port, room, username, password, lastUsedAt);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/core/data/saved_profile_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/core/data/saved_profile.dart test/core/data/saved_profile_test.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add SavedProfile domain model"
```

---

## Task 5: HistoryEntry model

**Files:**
- Create: `lib/core/data/history_entry.dart`
- Test: `test/core/data/history_entry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/data/history_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/history_entry.dart';

void main() {
  final played = DateTime(2026, 5, 29, 13);
  final base = HistoryEntry(
    id: 1,
    filePath: r'D:\videos\ep1.mkv',
    fileName: 'ep1.mkv',
    fileSizeBytes: 1024,
    durationMs: 600000,
    lastPositionMs: 12000,
    playedAt: played,
  );

  test('value equality', () {
    expect(
      base,
      HistoryEntry(
        id: 1,
        filePath: r'D:\videos\ep1.mkv',
        fileName: 'ep1.mkv',
        fileSizeBytes: 1024,
        durationMs: 600000,
        lastPositionMs: 12000,
        playedAt: played,
      ),
    );
  });

  test('copyWith updates position', () {
    expect(base.copyWith(lastPositionMs: 30000).lastPositionMs, 30000);
    expect(base.copyWith(lastPositionMs: 30000).fileName, base.fileName);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/core/data/history_entry_test.dart`
Expected: FAIL — `history_entry.dart` not found.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/data/history_entry.dart
import 'package:flutter/foundation.dart';

/// A file the user has watched, with the position to resume from.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.durationMs,
    required this.lastPositionMs,
    required this.playedAt,
  });

  final int id;
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final int? durationMs;
  final int lastPositionMs;
  final DateTime playedAt;

  HistoryEntry copyWith({
    int? id,
    String? filePath,
    String? fileName,
    int? fileSizeBytes,
    int? durationMs,
    int? lastPositionMs,
    DateTime? playedAt,
  }) {
    return HistoryEntry(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationMs: durationMs ?? this.durationMs,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      playedAt: playedAt ?? this.playedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryEntry &&
      other.id == id &&
      other.filePath == filePath &&
      other.fileName == fileName &&
      other.fileSizeBytes == fileSizeBytes &&
      other.durationMs == durationMs &&
      other.lastPositionMs == lastPositionMs &&
      other.playedAt == playedAt;

  @override
  int get hashCode => Object.hash(id, filePath, fileName, fileSizeBytes,
      durationMs, lastPositionMs, playedAt);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/core/data/history_entry_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/core/data/history_entry.dart test/core/data/history_entry_test.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add HistoryEntry domain model"
```

---

## Task 6: Abstract store interfaces

**Files:**
- Create: `lib/core/data/stores.dart`

No test of its own (interfaces only; exercised by Tasks 8–9 and 10). It must compile.

- [ ] **Step 1: Write the interfaces**

```dart
// lib/core/data/stores.dart
import 'history_entry.dart';
import 'saved_profile.dart';

/// Commands-in / streams-out access to saved connection profiles.
abstract class ProfileStore {
  /// Live list, most-recently-used first.
  Stream<List<SavedProfile>> watchProfiles();

  /// Insert or update the matching (server, port, room, username) profile and
  /// stamp it as just-used. [name] is the display label (usually the room).
  Future<void> saveUsed({
    required String name,
    required String server,
    required int port,
    required String room,
    required String username,
    String? password,
  });

  Future<void> delete(int id);
}

/// Commands-in / streams-out access to watch history.
abstract class HistoryStore {
  /// Live list, most-recently-played first.
  Stream<List<HistoryEntry>> watchRecent({int limit = 6});

  /// Record (or refresh) that [filePath] was opened. Keeps the existing
  /// [lastPositionMs]; updates name/size/duration and bumps playedAt.
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
  });

  /// Update the resume position for an already-recorded file (no-op if absent).
  Future<void> updatePosition({
    required String filePath,
    required int positionMs,
  });
}
```

- [ ] **Step 2: Analyze**

Run: `$FLUTTER analyze lib/core/data/stores.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/core/data/stores.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add ProfileStore/HistoryStore interfaces"
```

---

## Task 7: Drift database + codegen

**Files:**
- Create: `lib/core/data/app_database.dart`
- Generated: `lib/core/data/app_database.g.dart` (by build_runner — do not hand-edit)

- [ ] **Step 1: Write the drift schema**

```dart
// lib/core/data/app_database.dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('ProfileRow')
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get server => text()();
  IntColumn get port => integer()();
  TextColumn get room => text()();
  TextColumn get username => text()();
  TextColumn get password => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {server, port, room, username},
      ];
}

@DataClassName('HistoryRow')
class HistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text().unique()();
  TextColumn get fileName => text()();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get lastPositionMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get playedAt => dateTime()();
}

@DriftDatabase(tables: [Profiles, HistoryEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

/// Opens the on-disk database under the app's support directory
/// (Windows: %APPDATA%\com.example\meowwatch\meowwatch.db or similar).
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'meowwatch.db'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}
```

- [ ] **Step 2: Run code generation**

Run: `$FLUTTER pub run build_runner build --delete-conflicting-outputs`
Expected: "Succeeded" — creates `lib/core/data/app_database.g.dart` with `_$AppDatabase`, `ProfileRow`, `ProfilesCompanion`, `HistoryRow`, `HistoryEntriesCompanion`.

- [ ] **Step 3: Analyze**

Run: `$FLUTTER analyze lib/core/data/app_database.dart lib/core/data/app_database.g.dart`
Expected: "No issues found!"
(If the generated file trips a lint, add `// ignore_for_file: type=lint` at the top of `app_database.g.dart` — generated code is exempt.)

- [ ] **Step 4: Commit (including generated file)**

```bash
git -C "D:/Repos/MeowWatch" add lib/core/data/app_database.dart lib/core/data/app_database.g.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add drift AppDatabase with profiles + history tables"
```

---

## Task 8: DriftProfileStore

**Files:**
- Create: `lib/core/data/drift_stores.dart` (ProfileStore half; HistoryStore added in Task 9)
- Test: `test/core/data/drift_profile_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/data/drift_profile_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/drift_stores.dart';

void main() {
  late AppDatabase db;
  late DriftProfileStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftProfileStore(db);
  });

  tearDown(() async => db.close());

  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('saveUsed inserts a new profile', () async {
    await store.saveUsed(
      name: 'cozy-fox-42',
      server: 'syncplay.pl',
      port: 8999,
      room: 'cozy-fox-42',
      username: 'lin',
    );
    await tick();
    final list = await store.watchProfiles().first;
    expect(list, hasLength(1));
    expect(list.single.room, 'cozy-fox-42');
    expect(list.single.password, isNull);
    expect(list.single.lastUsedAt, isNotNull);
  });

  test('saveUsed on the same room/user updates instead of duplicating',
      () async {
    await store.saveUsed(
      name: 'r',
      server: 's',
      port: 1,
      room: 'r',
      username: 'u',
    );
    await store.saveUsed(
      name: 'r',
      server: 's',
      port: 1,
      room: 'r',
      username: 'u',
      password: 'secret',
    );
    final list = await store.watchProfiles().first;
    expect(list, hasLength(1));
    expect(list.single.password, 'secret');
  });

  test('watchProfiles orders most-recently-used first', () async {
    await store.saveUsed(name: 'a', server: 's', port: 1, room: 'a', username: 'u');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.saveUsed(name: 'b', server: 's', port: 1, room: 'b', username: 'u');
    final list = await store.watchProfiles().first;
    expect(list.map((p) => p.room).toList(), ['b', 'a']);
  });

  test('delete removes a profile', () async {
    await store.saveUsed(name: 'a', server: 's', port: 1, room: 'a', username: 'u');
    final saved = (await store.watchProfiles().first).single;
    await store.delete(saved.id);
    expect(await store.watchProfiles().first, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/core/data/drift_profile_store_test.dart`
Expected: FAIL — `drift_stores.dart` / `DriftProfileStore` not found.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/data/drift_stores.dart
import 'package:drift/drift.dart';

import 'app_database.dart';
import 'history_entry.dart';
import 'saved_profile.dart';
import 'stores.dart';

class DriftProfileStore implements ProfileStore {
  DriftProfileStore(this._db);

  final AppDatabase _db;

  @override
  Stream<List<SavedProfile>> watchProfiles() {
    final query = _db.select(_db.profiles)
      ..orderBy([
        (t) => OrderingTerm(expression: t.lastUsedAt, mode: OrderingMode.desc),
      ]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
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
    final existing = await (_db.select(_db.profiles)
          ..where((t) =>
              t.server.equals(server) &
              t.port.equals(port) &
              t.room.equals(room) &
              t.username.equals(username)))
        .getSingleOrNull();

    final companion = ProfilesCompanion(
      name: Value(name),
      server: Value(server),
      port: Value(port),
      room: Value(room),
      username: Value(username),
      password: Value(password),
      lastUsedAt: Value(DateTime.now()),
    );

    if (existing == null) {
      await _db.into(_db.profiles).insert(companion);
    } else {
      await (_db.update(_db.profiles)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
  }

  @override
  Future<void> delete(int id) =>
      (_db.delete(_db.profiles)..where((t) => t.id.equals(id))).go();

  SavedProfile _toModel(ProfileRow r) => SavedProfile(
        id: r.id,
        name: r.name,
        server: r.server,
        port: r.port,
        room: r.room,
        username: r.username,
        password: r.password,
        lastUsedAt: r.lastUsedAt,
      );
}

// DriftHistoryStore is added in Task 9.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/core/data/drift_profile_store_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/core/data/drift_stores.dart test/core/data/drift_profile_store_test.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add DriftProfileStore"
```

---

## Task 9: DriftHistoryStore

**Files:**
- Modify: `lib/core/data/drift_stores.dart` (append `DriftHistoryStore`)
- Test: `test/core/data/drift_history_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/data/drift_history_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/drift_stores.dart';

void main() {
  late AppDatabase db;
  late DriftHistoryStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftHistoryStore(db);
  });

  tearDown(() async => db.close());

  test('recordOpen inserts a history entry', () async {
    await store.recordOpen(
      filePath: r'D:\v\ep1.mkv',
      fileName: 'ep1.mkv',
      fileSizeBytes: 2048,
      durationMs: 600000,
    );
    final list = await store.watchRecent().first;
    expect(list, hasLength(1));
    expect(list.single.fileName, 'ep1.mkv');
    expect(list.single.lastPositionMs, 0);
  });

  test('recordOpen on the same path keeps last position, refreshes playedAt',
      () async {
    await store.recordOpen(
        filePath: r'D:\v\ep1.mkv', fileName: 'ep1.mkv', fileSizeBytes: 1);
    await store.updatePosition(filePath: r'D:\v\ep1.mkv', positionMs: 42000);
    await store.recordOpen(
        filePath: r'D:\v\ep1.mkv', fileName: 'ep1.mkv', fileSizeBytes: 1);
    final list = await store.watchRecent().first;
    expect(list, hasLength(1));
    expect(list.single.lastPositionMs, 42000);
  });

  test('updatePosition on an unknown path is a no-op', () async {
    await store.updatePosition(filePath: r'D:\nope.mkv', positionMs: 100);
    expect(await store.watchRecent().first, isEmpty);
  });

  test('watchRecent orders newest first and honors limit', () async {
    await store.recordOpen(filePath: 'a', fileName: 'a', fileSizeBytes: 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.recordOpen(filePath: 'b', fileName: 'b', fileSizeBytes: 1);
    final list = await store.watchRecent(limit: 1).first;
    expect(list.map((e) => e.fileName).toList(), ['b']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/core/data/drift_history_store_test.dart`
Expected: FAIL — `DriftHistoryStore` not found.

- [ ] **Step 3: Append the implementation**

Replace the trailing comment `// DriftHistoryStore is added in Task 9.` in `lib/core/data/drift_stores.dart` with:

```dart
class DriftHistoryStore implements HistoryStore {
  DriftHistoryStore(this._db);

  final AppDatabase _db;

  @override
  Stream<List<HistoryEntry>> watchRecent({int limit = 6}) {
    final query = _db.select(_db.historyEntries)
      ..orderBy([
        (t) => OrderingTerm(expression: t.playedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  @override
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
  }) async {
    final existing = await (_db.select(_db.historyEntries)
          ..where((t) => t.filePath.equals(filePath)))
        .getSingleOrNull();

    if (existing == null) {
      await _db.into(_db.historyEntries).insert(
            HistoryEntriesCompanion.insert(
              filePath: filePath,
              fileName: fileName,
              fileSizeBytes: Value(fileSizeBytes),
              durationMs: Value(durationMs),
              playedAt: DateTime.now(),
            ),
          );
    } else {
      await (_db.update(_db.historyEntries)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        HistoryEntriesCompanion(
          fileName: Value(fileName),
          fileSizeBytes: Value(fileSizeBytes),
          durationMs: Value(durationMs ?? existing.durationMs),
          playedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  @override
  Future<void> updatePosition({
    required String filePath,
    required int positionMs,
  }) =>
      (_db.update(_db.historyEntries)..where((t) => t.filePath.equals(filePath)))
          .write(HistoryEntriesCompanion(lastPositionMs: Value(positionMs)));

  HistoryEntry _toModel(HistoryRow r) => HistoryEntry(
        id: r.id,
        filePath: r.filePath,
        fileName: r.fileName,
        fileSizeBytes: r.fileSizeBytes,
        durationMs: r.durationMs,
        lastPositionMs: r.lastPositionMs,
        playedAt: r.playedAt,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/core/data/drift_history_store_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/core/data/drift_stores.dart test/core/data/drift_history_store_test.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add DriftHistoryStore"
```

---

## Task 10: ConnectScreen widget

**Files:**
- Create: `lib/ui/connect/connect_screen.dart`
- Test: `test/ui/connect/connect_screen_test.dart`

The screen talks ONLY to the abstract stores + an `onConnect` callback (navigation lives in `app.dart`, so the widget stays testable without media_kit). `ConnectScreen` saves the profile, then calls `onConnect(config)`.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/ui/connect/connect_screen_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/saved_profile.dart';
import 'package:meowwatch/core/data/stores.dart';
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

  @override
  Stream<List<HistoryEntry>> watchRecent({int limit = 6}) async* {
    yield List.unmodifiable(recent);
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
}

void main() {
  late _FakeProfileStore profiles;
  late _FakeHistoryStore history;
  RoomConfig? connected;

  Future<void> pump(WidgetTester tester) async {
    connected = null;
    await tester.pumpWidget(MaterialApp(
      home: ConnectScreen(
        profiles: profiles,
        history: history,
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
    profiles.profiles.add(SavedProfile(
      id: 1,
      name: 'cozy-fox-42',
      server: 'syncplay.pl',
      port: 8999,
      room: 'cozy-fox-42',
      username: 'lin',
      password: null,
      lastUsedAt: DateTime(2026, 5, 29),
    ));
    await pump(tester);
    expect(find.text('cozy-fox-42'), findsOneWidget);
  });

  testWidgets('Start new room generates a code and connects', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-name')), 'lin');
    await tester.tap(find.byKey(const Key('connect-start-new')));
    await tester.pump();
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
    await tester.tap(find.byKey(const Key('connect-delete-7')));
    await tester.pump();
    expect(profiles.deleted, [7]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/ui/connect/connect_screen_test.dart`
Expected: FAIL — `connect_screen.dart` not found.

- [ ] **Step 3: Write the implementation**

```dart
// lib/ui/connect/connect_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/connect/room_code.dart';
import '../../core/connect/room_config.dart';
import '../../core/data/history_entry.dart';
import '../../core/data/saved_profile.dart';
import '../../core/data/stores.dart';
import '../../core/sync/syncplay_constants.dart';

// Cozy theme (hardcoded until Phase 5).
const _bg = Color(0xFF1A1410);
const _card = Color(0xF2241B14);
const _amber = Color(0xFFD4A574);
const _cream = Color(0xFFF5E6D3);
const _dim = Color(0x99F5E6D3);
const _border = Color(0x55D4A574);

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    required this.profiles,
    required this.history,
    required this.onConnect,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;
  final Future<void> Function(RoomConfig config) onConnect;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController(text: SyncplayConstants.defaultServer);
  final _port = TextEditingController(text: '${SyncplayConstants.defaultPort}');
  final _password = TextEditingController();
  bool _advancedOpen = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _server.dispose();
    _port.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _username {
    final typed = _name.text.trim();
    return typed.isEmpty ? 'meow' : typed;
  }

  String get _server_ => _server.text.trim().isEmpty
      ? SyncplayConstants.defaultServer
      : _server.text.trim();

  int get _portValue =>
      int.tryParse(_port.text.trim()) ?? SyncplayConstants.defaultPort;

  String? get _passwordValue =>
      _password.text.isEmpty ? null : _password.text;

  Future<void> _connect(RoomConfig config) async {
    await widget.profiles.saveUsed(
      name: config.room,
      server: config.server,
      port: config.port,
      room: config.room,
      username: config.username,
      password: config.password,
    );
    if (!mounted) return;
    await widget.onConnect(config);
  }

  Future<void> _startNewRoom() async {
    final room = generateRoomCode();
    await Clipboard.setData(ClipboardData(text: room));
    await _connect(RoomConfig(
      server: _server_,
      port: _portValue,
      room: room,
      username: _username,
      password: _passwordValue,
    ));
  }

  Future<void> _joinTypedCode() async {
    final room = _code.text.trim();
    if (room.isEmpty) return;
    await _connect(RoomConfig(
      server: _server_,
      port: _portValue,
      room: room,
      username: _username,
      password: _passwordValue,
    ));
  }

  Future<void> _connectProfile(SavedProfile p) async {
    _name.text = p.username;
    await _connect(RoomConfig(
      server: p.server,
      port: p.port,
      room: p.room,
      username: p.username,
      password: p.password,
    ));
  }

  Future<void> _resumeHistory(HistoryEntry entry, SavedProfile? recent) async {
    final room = recent?.room ?? generateRoomCode();
    await _connect(RoomConfig(
      server: recent?.server ?? _server_,
      port: recent?.port ?? _portValue,
      room: room,
      username: _username,
      password: recent?.password ?? _passwordValue,
      resumeFilePath: entry.filePath,
      resumePositionMs: entry.lastPositionMs,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: StreamBuilder<List<SavedProfile>>(
              stream: widget.profiles.watchProfiles(),
              initialData: const [],
              builder: (context, profileSnap) {
                final savedProfiles = profileSnap.data ?? const [];
                final mostRecent =
                    savedProfiles.isEmpty ? null : savedProfiles.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('MeowWatch',
                        style: TextStyle(
                            color: _cream,
                            fontSize: 30,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Watch together, in sync.',
                        style: TextStyle(color: _dim, fontSize: 14)),
                    const SizedBox(height: 24),
                    _label('Your name'),
                    _textField(
                        key: const Key('connect-name'),
                        controller: _name,
                        hint: 'e.g. lin'),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('connect-start-new'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _amber,
                        foregroundColor: _bg,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _startNewRoom,
                      child: const Text('Start new room',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    const Text('A code is generated and copied to clipboard.',
                        style: TextStyle(color: _dim, fontSize: 12)),
                    const SizedBox(height: 20),
                    _label('Enter code from friend'),
                    Row(children: [
                      Expanded(
                        child: _textField(
                            key: const Key('connect-code'),
                            controller: _code,
                            hint: 'cozy-fox-42'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('connect-join'),
                        style: FilledButton.styleFrom(
                            backgroundColor: _card, foregroundColor: _cream),
                        onPressed: _joinTypedCode,
                        child: const Text('Join'),
                      ),
                    ]),
                    if (savedProfiles.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _label('Saved rooms'),
                      ...savedProfiles.map((p) =>
                          _profileCard(p, isMostRecent: p == mostRecent)),
                    ],
                    _ContinueWatching(
                      history: widget.history,
                      onResume: (entry) => _resumeHistory(entry, mostRecent),
                    ),
                    const SizedBox(height: 16),
                    _advancedSection(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(color: _dim, fontSize: 13)),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    Key? key,
    bool obscure = false,
  }) {
    return TextField(
      key: key,
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: _cream),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _dim),
        filled: true,
        fillColor: _card,
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _amber),
        ),
      ),
    );
  }

  Widget _profileCard(SavedProfile p, {required bool isMostRecent}) {
    return Card(
      color: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border),
      ),
      child: ListTile(
        onTap: () => _connectProfile(p),
        leading: Icon(Icons.circle,
            size: 10, color: isMostRecent ? const Color(0xFF7BC47F) : _dim),
        title: Text(p.name, style: const TextStyle(color: _cream)),
        subtitle: Text('${p.username} · ${p.server}',
            style: const TextStyle(color: _dim, fontSize: 12)),
        trailing: IconButton(
          key: Key('connect-delete-${p.id}'),
          icon: const Icon(Icons.close, color: _dim, size: 18),
          onPressed: () => widget.profiles.delete(p.id),
        ),
      ),
    );
  }

  Widget _advancedSection() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('connect-advanced'),
        initiallyExpanded: _advancedOpen,
        onExpansionChanged: (v) => setState(() => _advancedOpen = v),
        title: const Text('Advanced', style: TextStyle(color: _dim)),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          _label('Server'),
          _textField(controller: _server, hint: SyncplayConstants.defaultServer),
          const SizedBox(height: 12),
          _label('Port'),
          _textField(controller: _port, hint: '${SyncplayConstants.defaultPort}'),
          const SizedBox(height: 12),
          _label('Room password (optional)'),
          _textField(controller: _password, hint: 'leave blank for none'),
        ],
      ),
    );
  }
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({required this.history, required this.onResume});

  final HistoryStore history;
  final void Function(HistoryEntry entry) onResume;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HistoryEntry>>(
      stream: history.watchRecent(),
      initialData: const [],
      builder: (context, snap) {
        final recent = snap.data ?? const [];
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child:
                  Text('Continue watching', style: TextStyle(color: _dim, fontSize: 13)),
            ),
            ...recent.map(
              (e) => Card(
                color: _card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: _border),
                ),
                child: ListTile(
                  key: Key('continue-${e.id}'),
                  onTap: () => onResume(e),
                  leading: const Icon(Icons.play_circle, color: _amber),
                  title: Text(e.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _cream)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/ui/connect/connect_screen_test.dart`
Expected: PASS (4 tests). (If "Start new room" tap warns about off-screen tapping, the test already uses keys; no scroll needed at maxWidth 460. If a future test scrolls, use `tester.ensureVisible` first.)

- [ ] **Step 5: Analyze + commit**

```bash
$FLUTTER analyze
git -C "D:/Repos/MeowWatch" add lib/ui/connect/connect_screen.dart test/ui/connect/connect_screen_test.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: add ConnectScreen (profiles, new room, enter code, continue watching)"
```

---

## Task 11: Make HomeScreen config-driven (auto-connect, Leave, history)

**Files:**
- Modify: `lib/ui/home_screen.dart`

HomeScreen stops owning the connect bar. It takes a `RoomConfig` + `HistoryStore`, connects on `initState`, records history on load, periodically saves resume position, resumes a file if `config.resumeFilePath` is set, and shows a small **Leave** button that disconnects and pops back to Connect.

- [ ] **Step 1: Update imports + constructor + remove dev bar**

Replace the import block (lines 1–19) with (drops `dev_connect_bar.dart`, adds data imports):

```dart
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/chat/chat_store.dart';
import '../core/connect/room_config.dart';
import '../core/data/stores.dart';
import '../core/sync/peer_state.dart';
import '../core/sync/playback_sync_bridge.dart';
import '../core/sync/syncplay_client.dart';
import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';
import 'chat/chat_overlay.dart';
import 'chat/chat_overlay_layout.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'video_surface.dart';
```

Replace the widget declaration (lines 21–26) with:

```dart
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.config,
    required this.history,
    super.key,
  });

  final RoomConfig config;
  final HistoryStore history;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
```

- [ ] **Step 2: Add history timer field + auto-connect in initState**

In `_HomeScreenState`, add a field next to the other `Timer?` fields:

```dart
  Timer? _historyTimer;
```

Change `_username` initialization — replace `String _username = '';` with:

```dart
  late String _username;
```

At the END of `initState()` (after the `_presenceSub = ...` block, before the closing `}`), add:

```dart
    _username = widget.config.username;
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_saveResumePosition());
    });
    unawaited(_sync.connect(
      server: widget.config.server,
      port: widget.config.port,
      username: widget.config.username,
      room: widget.config.room,
      password: widget.config.password,
    ));
    final resume = widget.config.resumeFilePath;
    if (resume != null) {
      unawaited(_resume(resume, widget.config.resumePositionMs));
    }
```

- [ ] **Step 3: Cancel timer + final save in dispose**

In `dispose()`, add at the top (before `_peekTimer?.cancel();`):

```dart
    _historyTimer?.cancel();
    unawaited(_saveResumePosition());
```

- [ ] **Step 4: Record history on load; add resume + save helpers; drop _connect**

Replace the existing `_load` method with:

```dart
  /// Load (but do not auto-play). In a room, hitting play yourself starts both
  /// of you in sync; auto-playing on load made the two clients fight at 0.
  Future<void> _load(String path) async {
    await _core.load(path);
    await _announceCurrentFile();
    await _recordOpen(path);
  }

  Future<void> _resume(String path, int positionMs) async {
    await _load(path);
    if (positionMs > 0) {
      await _core.seek(Duration(milliseconds: positionMs));
    }
  }

  Future<void> _recordOpen(String path) async {
    final state = _core.state;
    var size = 0;
    try {
      size = await File(path).length();
    } on FileSystemException {
      size = 0;
    }
    await widget.history.recordOpen(
      filePath: path,
      fileName: state.fileName ?? path,
      fileSizeBytes: size,
      durationMs: state.duration?.inMilliseconds,
    );
  }

  Future<void> _saveResumePosition() async {
    final state = _core.state;
    final path = state.filePath;
    if (path == null) return;
    await widget.history.updatePosition(
      filePath: path,
      positionMs: state.position.inMilliseconds,
    );
  }

  Future<void> _leave() async {
    _historyTimer?.cancel();
    await _saveResumePosition();
    await _sync.disconnect();
    if (mounted) Navigator.of(context).pop();
  }
```

Delete the entire old `_connect({...})` method (the block that set `_username` and called `_sync.connect`).

> Note: confirm `_core.seek(Duration)` and `_sync.disconnect()` exist (they back the controls + were used by the dev flow). If `SyncplayClient` exposes a different disconnect name, use that; if `VideoCore` lacks `seek`, use its existing seek method name. Adjust the two call sites only.

- [ ] **Step 5: Rebuild `build` without the Column/dev bar; add Leave button**

Replace the entire `build` method body's outer structure. Change the `Scaffold` so its `body` is the `Focus`-wrapped content directly (no `Column`, no `DevConnectBar`), and add a Leave button into the `Stack`. Replace from `return Scaffold(` down to the matching close of that `Scaffold` with:

```dart
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            setState(() => _chatLayout = _chatLayout.toggle());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: VideoDropTarget(
          onFileDropped: _handleDropped,
          child: StreamBuilder<PlaybackState>(
            stream: _core.stateStream,
            initialData: _core.state,
            builder: (context, snapshot) {
              final state = snapshot.data!;
              final hint = _syncHint;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (state.fileName == null)
                    EmptyState(onBrowse: _browse)
                  else
                    VideoSurface(core: _core),
                  if (state.fileName != null && hint != null)
                    Align(
                      alignment: const Alignment(0, -0.8),
                      child: _SyncHintBanner(text: hint),
                    ),
                  if (state.fileName != null)
                    ChatOverlay(
                      messages: _messages,
                      myUsername: _username,
                      collapsed: _chatLayout.collapsed,
                      corner: _chatLayout.corner,
                      pulsing: _peekPulsing,
                      onSend: _chat.send,
                      onToggleCollapsed: () => setState(
                          () => _chatLayout = _chatLayout.toggle()),
                      onSnap: (result) => setState(
                          () => _chatLayout = _chatLayout.applySnap(result)),
                    ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _LeaveButton(onLeave: _leave),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
```

- [ ] **Step 6: Add the `_LeaveButton` widget**

At the bottom of the file (after `_SyncHintBanner`), add:

```dart
class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onLeave});

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC1A1410),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x55D4A574)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onLeave,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back, size: 16, color: Color(0xFFF5E6D3)),
              SizedBox(width: 6),
              Text('Leave',
                  style: TextStyle(color: Color(0xFFF5E6D3), fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Analyze**

Run: `$FLUTTER analyze lib/ui/home_screen.dart`
Expected: "No issues found!" (Errors here are usually a wrong `seek`/`disconnect` name — fix the call site to match the real API.)

- [ ] **Step 8: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/ui/home_screen.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: drive HomeScreen from RoomConfig; add Leave + history recording"
```

---

## Task 12: Wire app + main; remove dev bar

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/main.dart`
- Delete: `lib/ui/dev_connect_bar.dart`

- [ ] **Step 1: Rewrite `app.dart` to host ConnectScreen**

```dart
// lib/app.dart
import 'package:flutter/material.dart';

import 'core/connect/room_config.dart';
import 'core/data/stores.dart';
import 'ui/connect/connect_screen.dart';
import 'ui/home_screen.dart';

class MeowWatchApp extends StatelessWidget {
  const MeowWatchApp({
    required this.profiles,
    required this.history,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeowWatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4A574),
          brightness: Brightness.dark,
        ),
      ),
      home: Builder(
        builder: (context) => ConnectScreen(
          profiles: profiles,
          history: history,
          onConnect: (RoomConfig config) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HomeScreen(config: config, history: history),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Rewrite `main.dart` to open the DB + build stores**

```dart
// lib/main.dart
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/data/app_database.dart';
import 'core/data/drift_stores.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final db = await openAppDatabase();

  runApp(MeowWatchApp(
    profiles: DriftProfileStore(db),
    history: DriftHistoryStore(db),
  ));
}
```

> Note: keep whatever `windowManager` setup (size/options) the current `main.dart` had if it differs from the above — preserve those calls, only add the DB + stores wiring. Read the current `main.dart` first and merge rather than blindly overwrite.

- [ ] **Step 3: Delete the dev connect bar**

```bash
git -C "D:/Repos/MeowWatch" rm lib/ui/dev_connect_bar.dart
```

- [ ] **Step 4: Analyze full project**

Run: `$FLUTTER analyze`
Expected: "No issues found!" (no lingering references to `DevConnectBar`).

- [ ] **Step 5: Commit**

```bash
git -C "D:/Repos/MeowWatch" add lib/app.dart lib/main.dart
git -C "D:/Repos/MeowWatch" commit -m "feat: route ConnectScreen→HomeScreen; open DB in main; remove dev bar"
```

---

## Task 13: Full verification + manual two-instance test

**Files:** none (verification only)

- [ ] **Step 1: Run the whole suite**

Run: `$FLUTTER test`
Expected: all tests pass (existing Phase 1–3 suite + the new Task 2–10 tests).

- [ ] **Step 2: Analyze**

Run: `$FLUTTER analyze`
Expected: "No issues found!"

- [ ] **Step 3: Build Release (kill running instances first)**

```bash
powershell -Command "Stop-Process -Name meowwatch -Force -ErrorAction SilentlyContinue"
$FLUTTER build windows
```

Expected: `Built build\windows\x64\runner\Release\meowwatch.exe`.
Confirm `build/windows/x64/runner/Release/data/app.so` mtime is fresh (Dart changes compiled in).

- [ ] **Step 4: Manual two-instance test (user-driven — required before tagging)**

Launch two Release instances. Verify:
1. Connect screen shows greeting + Your name + Start new room + Enter code + Advanced.
2. Instance A "Start new room" → joins, room code copied to clipboard. Profile card appears under "Saved rooms".
3. Instance B "Enter code from friend" with A's code → both connected, presence shows the peer.
4. Load a file in A → plays; B loads the same file → play/pause/seek stay in sync (Phase 2 behavior intact).
5. "Continue watching" appears after a file is watched and resumes position on click.
6. Leave button returns to Connect; saved room card re-connects.
7. Delete (×) removes a saved room card.

- [ ] **Step 5: Tag (only after the user confirms the manual test passes)**

```bash
git -C "D:/Repos/MeowWatch" tag phase-4-complete
```

Then update `docs/ROADMAP.md` (mark Phase 4 ✅ with the tag + plan link) and the project memory file, in the same commit.

---

## Self-Review (completed by plan author)

- **Spec coverage:** Connect screen (greeting, profile cards w/ last-used green dot, Start new room + clipboard, Enter code, Advanced collapsible) → Task 10. SQLite via drift → Tasks 1, 7. Profiles table + history table → Task 7; stores → Tasks 8–9. Watch history "Continue watching" → Task 10 + recording in Task 11. Routing + Leave → Tasks 11–12. All four locked decisions covered: plaintext optional password (Task 7 nullable column, Task 10 advanced field, no hashing), include history (Tasks 9–11), Leave button (Task 11), auto-save deletable profiles (Task 10 `_connect` calls `saveUsed`; delete icon).
- **Placeholder scan:** none — every code step has full code; every run step has a command + expected result.
- **Type consistency:** `ProfileStore.saveUsed` named params match between `stores.dart` (Task 6), `DriftProfileStore` (Task 8), the fake (Task 10), and the call site (Task 10 `_connect`). `HistoryStore.recordOpen/updatePosition/watchRecent` signatures match across Tasks 6/9/10/11. `RoomConfig` fields used in Task 10/11 match Task 3. Drift row names disambiguated via `@DataClassName('ProfileRow'/'HistoryRow')` so they don't collide with domain models `SavedProfile`/`HistoryEntry`.
- **Two API call sites flagged for verification at execution time** (Task 11 Step 4 note): `_core.seek(Duration)` and `_sync.disconnect()` — confirm exact method names against the real `VideoCore`/`SyncplayClient` before relying on them; adjust only the call sites if they differ.
