# Phase 5 — Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ~57 hardcoded Cozy color literals across 12 widget files with a swappable `ThemeExtension<MeowColors>`, ship Cozy (default) + Cinema Noir + Glass Aurora presets, add a switcher on the Connect screen and in the control bar, and persist the choice in SQLite.

**Architecture:** A `MeowColors` `ThemeExtension` carries every semantic color slot (plus gradient / glass-blur / title-font fields) on Material `ThemeData`. The app root holds the active `MeowThemeId`, builds a `ThemeData` per preset, and swaps `MaterialApp.theme` (Flutter animates the cross-fade). Widgets read colors via a `context.meow` getter. The choice is saved to a new drift `Settings` key/value table via a `SettingsStore`.

**Tech Stack:** Flutter 3.44 / Dart 3.12 (Puro), `drift` SQLite, `flutter_test` + `mocktail`.

**Spec:** `docs/superpowers/specs/2026-05-29-phase-5-themes-design.md`

**Tooling note:** Flutter is NOT on PATH. Use the absolute binary in every command:
`%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat` (shown below as `$FLUTTER`).

```bash
FLUTTER=%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat
```

**Color → slot mapping (canonical — used by the refactor tasks).** Every literal currently in the widget files maps to one of these. Opacity variants are produced from a base slot with `.withValues(alpha: …)` so all shades move together when the theme changes:

| current literal | meaning | replacement |
|---|---|---|
| `0xFFD4A574` | accent (amber) | `m.accent` |
| `0xCCD4A574` | accent 80% | `m.accent.withValues(alpha: 0.80)` |
| `0x55D4A574` | accent 33% = border | `m.border` |
| `0x33D4A574` | accent 20% | `m.accent.withValues(alpha: 0.20)` |
| `0xFF1A1410` | background | `m.background` |
| `0xCC1A1410` | background 80% | `m.background.withValues(alpha: 0.80)` |
| `0xF2241B14` | surface | `m.surface` |
| `0x55241B14` | surface 33% | `m.surface.withValues(alpha: 0.33)` |
| `0xFFF5E6D3` | text primary (cream) | `m.textPrimary` |
| `0x99F5E6D3` | text 60% = dim | `m.textDim` |
| `0x66F5E6D3` | text 40% | `m.textPrimary.withValues(alpha: 0.40)` |
| `0x55F5E6D3` | text 33% | `m.textPrimary.withValues(alpha: 0.33)` |
| `0x99000000` | black scrim 60% | `m.scrim.withValues(alpha: 0.60)` |
| `0xCC000000` | black scrim 80% | `m.scrim.withValues(alpha: 0.80)` |
| `0x00000000` | transparent | `Colors.transparent` (leave; not a theme color) |
| `0xFF7BC47F` | "most recent" online dot | `m.online` |

…where `m` is `context.meow` (or `Theme.of(context).extension<MeowColors>()!`).

---

### Task 1: `MeowColors` extension + presets + `MeowThemeId`

**Files:**
- Create: `lib/core/theme/meow_theme.dart`
- Test: `test/core/theme/meow_theme_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/meow_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';

void main() {
  group('MeowColors presets', () {
    test('cozy preserves the current hardcoded palette', () {
      const c = MeowColors.cozy;
      expect(c.background, const Color(0xFF1A1410));
      expect(c.surface, const Color(0xF2241B14));
      expect(c.accent, const Color(0xFFD4A574));
      expect(c.textPrimary, const Color(0xFFF5E6D3));
      expect(c.textDim, const Color(0x99F5E6D3));
      expect(c.border, const Color(0x55D4A574));
      expect(c.myBubble, const Color(0x33D4A574));
      expect(c.peerBubble, const Color(0x55241B14));
      expect(c.backgroundGradient, isNull);
      expect(c.glassBlur, 0);
      expect(c.titleFontFamily, isNull);
    });

    test('noir is black + gold with a serif title font', () {
      const c = MeowColors.noir;
      expect(c.background, const Color(0xFF000000));
      expect(c.accent, const Color(0xFFD4AF37));
      expect(c.titleFontFamily, isNotNull);
      expect(c.glassBlur, 0);
    });

    test('aurora has a gradient and glass blur', () {
      const c = MeowColors.aurora;
      expect(c.backgroundGradient, isNotNull);
      expect(c.glassBlur, greaterThan(0));
      expect(c.accent, const Color(0xFF7DF9C2));
    });
  });

  group('MeowColors lerp/copyWith', () {
    test('lerp at t=0 returns this palette values', () {
      const a = MeowColors.cozy;
      const b = MeowColors.noir;
      final mid = a.lerp(b, 0.0);
      expect(mid.accent, a.accent);
    });

    test('lerp at t=1 returns the other palette values', () {
      const a = MeowColors.cozy;
      const b = MeowColors.noir;
      final mid = a.lerp(b, 1.0);
      expect(mid.accent, b.accent);
    });

    test('copyWith overrides one slot only', () {
      const c = MeowColors.cozy;
      final c2 = c.copyWith(accent: const Color(0xFF112233));
      expect(c2.accent, const Color(0xFF112233));
      expect(c2.background, c.background);
    });
  });

  group('MeowThemeId', () {
    test('fromName maps known names and falls back to cozy', () {
      expect(MeowThemeId.fromName('noir'), MeowThemeId.noir);
      expect(MeowThemeId.fromName('aurora'), MeowThemeId.aurora);
      expect(MeowThemeId.fromName('bogus'), MeowThemeId.cozy);
      expect(MeowThemeId.fromName(null), MeowThemeId.cozy);
    });

    test('each id carries its preset colors', () {
      expect(MeowThemeId.cozy.colors, MeowColors.cozy);
      expect(MeowThemeId.noir.colors, MeowColors.noir);
      expect(MeowThemeId.aurora.colors, MeowColors.aurora);
    });
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$FLUTTER test test/core/theme/meow_theme_test.dart`
Expected: FAIL — `meow_theme.dart` / `MeowColors` does not exist (compile error).

- [ ] **Step 3: Implement `meow_theme.dart`**

```dart
// lib/core/theme/meow_theme.dart
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// All MeowWatch-specific colors + presentation flags, carried on ThemeData as
/// a ThemeExtension. Read it via `context.meow` (see meow_context.dart).
@immutable
class MeowColors extends ThemeExtension<MeowColors> {
  const MeowColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textDim,
    required this.border,
    required this.myBubble,
    required this.peerBubble,
    required this.scrim,
    required this.online,
    this.backgroundGradient,
    this.glassBlur = 0,
    this.titleFontFamily,
  });

  final Color background;
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textDim;
  final Color border;
  final Color myBubble;
  final Color peerBubble;

  /// Base black for shadows/scrims; widgets apply their own opacity.
  final Color scrim;

  /// "Most recent / online" status dot.
  final Color online;

  /// Non-null = paint the window background as this gradient instead of [background].
  final Gradient? backgroundGradient;

  /// >0 = frost the chat card / control bar with a BackdropFilter of this sigma.
  final double glassBlur;

  /// Non-null = render titles / chat header in this font family (serif for Noir).
  final String? titleFontFamily;

  static const cozy = MeowColors(
    background: Color(0xFF1A1410),
    surface: Color(0xF2241B14),
    accent: Color(0xFFD4A574),
    textPrimary: Color(0xFFF5E6D3),
    textDim: Color(0x99F5E6D3),
    border: Color(0x55D4A574),
    myBubble: Color(0x33D4A574),
    peerBubble: Color(0x55241B14),
    scrim: Color(0xFF000000),
    online: Color(0xFF7BC47F),
  );

  static const noir = MeowColors(
    background: Color(0xFF000000),
    surface: Color(0xF50C0C0C),
    accent: Color(0xFFD4AF37),
    textPrimary: Color(0xFFECECEC),
    textDim: Color(0x99ECECEC),
    border: Color(0x38D4AF37),
    myBubble: Color(0x29D4AF37),
    peerBubble: Color(0x0FFFFFFF),
    scrim: Color(0xFF000000),
    online: Color(0xFF7BC47F),
    titleFontFamily: 'serif',
  );

  static const aurora = MeowColors(
    background: Color(0xFF1E2A4A),
    surface: Color(0x1AFFFFFF),
    accent: Color(0xFF7DF9C2),
    textPrimary: Color(0xFFF0F4FF),
    textDim: Color(0xA6F0F4FF),
    border: Color(0x38FFFFFF),
    myBubble: Color(0x47A78BFA),
    peerBubble: Color(0x1AFFFFFF),
    scrim: Color(0xFF000000),
    online: Color(0xFF7DF9C2),
    backgroundGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2A1B4D), Color(0xFF1E3A5F), Color(0xFF0E3A4A)],
    ),
    glassBlur: 12,
  );

  @override
  MeowColors copyWith({
    Color? background,
    Color? surface,
    Color? accent,
    Color? textPrimary,
    Color? textDim,
    Color? border,
    Color? myBubble,
    Color? peerBubble,
    Color? scrim,
    Color? online,
    Gradient? backgroundGradient,
    double? glassBlur,
    String? titleFontFamily,
  }) {
    return MeowColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textDim: textDim ?? this.textDim,
      border: border ?? this.border,
      myBubble: myBubble ?? this.myBubble,
      peerBubble: peerBubble ?? this.peerBubble,
      scrim: scrim ?? this.scrim,
      online: online ?? this.online,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      glassBlur: glassBlur ?? this.glassBlur,
      titleFontFamily: titleFontFamily ?? this.titleFontFamily,
    );
  }

  @override
  MeowColors lerp(covariant ThemeExtension<MeowColors>? other, double t) {
    if (other is! MeowColors) return this;
    return MeowColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      border: Color.lerp(border, other.border, t)!,
      myBubble: Color.lerp(myBubble, other.myBubble, t)!,
      peerBubble: Color.lerp(peerBubble, other.peerBubble, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      online: Color.lerp(online, other.online, t)!,
      backgroundGradient:
          Gradient.lerp(backgroundGradient, other.backgroundGradient, t),
      glassBlur: lerpDouble(glassBlur, other.glassBlur, t) ?? glassBlur,
      titleFontFamily: t < 0.5 ? titleFontFamily : other.titleFontFamily,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MeowColors &&
      other.background == background &&
      other.surface == surface &&
      other.accent == accent &&
      other.textPrimary == textPrimary &&
      other.textDim == textDim &&
      other.border == border &&
      other.myBubble == myBubble &&
      other.peerBubble == peerBubble &&
      other.scrim == scrim &&
      other.online == online &&
      other.backgroundGradient == backgroundGradient &&
      other.glassBlur == glassBlur &&
      other.titleFontFamily == titleFontFamily;

  @override
  int get hashCode => Object.hash(
        background, surface, accent, textPrimary, textDim, border,
        myBubble, peerBubble, scrim, online, backgroundGradient,
        glassBlur, titleFontFamily,
      );
}

/// The three selectable presets. The enum name (`cozy`/`noir`/`aurora`) is the
/// persisted key; [label] is the user-facing name; [colors] is the palette.
enum MeowThemeId {
  cozy('Cozy', MeowColors.cozy),
  noir('Cinema Noir', MeowColors.noir),
  aurora('Glass Aurora', MeowColors.aurora);

  const MeowThemeId(this.label, this.colors);

  final String label;
  final MeowColors colors;

  static MeowThemeId fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => cozy);
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `$FLUTTER test test/core/theme/meow_theme_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/meow_theme.dart test/core/theme/meow_theme_test.dart
git commit -m "feat: add MeowColors theme extension + three presets"
```

---

### Task 2: `context.meow` getter + `themeDataFor`

**Files:**
- Create: `lib/core/theme/meow_context.dart`
- Test: `test/core/theme/meow_context_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/meow_context_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';

void main() {
  testWidgets('context.meow returns the active extension', (tester) async {
    late MeowColors seen;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.noir),
      home: Builder(builder: (context) {
        seen = context.meow;
        return const SizedBox();
      }),
    ));
    expect(seen.accent, MeowColors.noir.accent);
  });

  test('themeDataFor seeds the ColorScheme from the preset accent', () {
    final t = themeDataFor(MeowThemeId.aurora);
    expect(t.extension<MeowColors>(), MeowColors.aurora);
    expect(t.useMaterial3, isTrue);
    expect(t.brightness, Brightness.dark);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$FLUTTER test test/core/theme/meow_context_test.dart`
Expected: FAIL — `meow_context.dart` / `context.meow` / `themeDataFor` undefined.

- [ ] **Step 3: Implement `meow_context.dart`**

```dart
// lib/core/theme/meow_context.dart
import 'package:flutter/material.dart';

import 'meow_theme.dart';

/// Build a Material ThemeData for [id], carrying its MeowColors extension and a
/// dark ColorScheme seeded from the preset accent so stock Material widgets
/// stay coherent.
ThemeData themeDataFor(MeowThemeId id) {
  final c = id.colors;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: Brightness.dark,
    ),
    extensions: <ThemeExtension<dynamic>>[c],
  );
}

/// Ergonomic access to the active MeowColors: `context.meow.accent`.
extension MeowContext on BuildContext {
  MeowColors get meow => Theme.of(this).extension<MeowColors>()!;
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `$FLUTTER test test/core/theme/meow_context_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/meow_context.dart test/core/theme/meow_context_test.dart
git commit -m "feat: add context.meow getter and themeDataFor builder"
```

---

### Task 3: `Settings` table + migration + codegen

**Files:**
- Modify: `lib/core/data/app_database.dart`
- Regenerate: `lib/core/data/app_database.g.dart` (build_runner)
- Test: `test/core/data/settings_migration_test.dart`

- [ ] **Step 1: Write the failing migration test**

```dart
// test/core/data/settings_migration_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';

void main() {
  test('v2 schema exposes a usable Settings table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.settings).insert(
          SettingsCompanion.insert(key: 'theme', value: 'noir'),
        );
    final row = await (db.select(db.settings)
          ..where((t) => t.key.equals('theme')))
        .getSingle();
    expect(row.value, 'noir');
  });

  test('schemaVersion is 2', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 2);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$FLUTTER test test/core/data/settings_migration_test.dart`
Expected: FAIL — `db.settings` / `SettingsCompanion` undefined (table not declared yet).

- [ ] **Step 3: Add the table + migration to `app_database.dart`**

Add the table class after `HistoryEntries` (before the `@DriftDatabase` annotation):

```dart
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
```

Change the annotation and class body:

```dart
@DriftDatabase(tables: [Profiles, HistoryEntries, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(settings);
        },
      );
}
```

- [ ] **Step 4: Regenerate drift code**

Run: `$FLUTTER pub run build_runner build --delete-conflicting-outputs`
Expected: regenerates `app_database.g.dart` with `Settings`, `SettingRow`, `SettingsCompanion`, and `db.settings`. Build completes with "Succeeded".

- [ ] **Step 5: Run the test, verify it passes**

Run: `$FLUTTER test test/core/data/settings_migration_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/data/app_database.dart lib/core/data/app_database.g.dart test/core/data/settings_migration_test.dart
git commit -m "feat: add Settings key/value table with v1->v2 migration"
```

---

### Task 4: `SettingsStore` abstract + `DriftSettingsStore`

**Files:**
- Create: `lib/core/data/settings_store.dart`
- Modify: `lib/core/data/drift_stores.dart` (add `DriftSettingsStore`)
- Test: `test/core/data/settings_store_test.dart`

> Check `lib/core/data/drift_stores.dart` first to match the existing constructor pattern (`DriftProfileStore(this._db)` taking an `AppDatabase`). Add `DriftSettingsStore` there alongside the others.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/data/settings_store_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/app_database.dart';
import 'package:meowwatch/core/data/drift_stores.dart';
import 'package:meowwatch/core/data/settings_store.dart';

void main() {
  late AppDatabase db;
  late SettingsStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftSettingsStore(db);
  });
  tearDown(() => db.close());

  test('get returns null for a missing key', () async {
    expect(await store.get('theme'), isNull);
  });

  test('set then get round-trips', () async {
    await store.set('theme', 'aurora');
    expect(await store.get('theme'), 'aurora');
  });

  test('set overwrites an existing key', () async {
    await store.set('theme', 'noir');
    await store.set('theme', 'cozy');
    expect(await store.get('theme'), 'cozy');
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$FLUTTER test test/core/data/settings_store_test.dart`
Expected: FAIL — `settings_store.dart` / `DriftSettingsStore` undefined.

- [ ] **Step 3: Implement the abstract store**

```dart
// lib/core/data/settings_store.dart
/// Key for the persisted theme choice (value = MeowThemeId.name).
const String kThemeSettingKey = 'theme';

/// Commands-in access to persisted key/value app settings.
abstract class SettingsStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
```

- [ ] **Step 4: Implement `DriftSettingsStore` in `drift_stores.dart`**

Add the import at the top of `lib/core/data/drift_stores.dart`:

```dart
import 'settings_store.dart';
```

Add the class (matching the file's existing style):

```dart
class DriftSettingsStore implements SettingsStore {
  DriftSettingsStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> set(String key, String value) {
    return _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }
}
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `$FLUTTER test test/core/data/settings_store_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/data/settings_store.dart lib/core/data/drift_stores.dart test/core/data/settings_store_test.dart
git commit -m "feat: add SettingsStore + DriftSettingsStore"
```

---

### Task 5: App-root theme state + persistence wiring

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/main.dart`
- Test: `test/app_theme_test.dart`

This task threads `currentTheme` + `onThemeChanged` into `ConnectScreen` and `HomeScreen`. Those widgets do not yet accept these params — add them as **required** params here and update the call sites; the switcher UI inside them is built in Tasks 8–9. To keep this task compiling, add the params to each widget's constructor now (store them; unused until Tasks 8–9).

- [ ] **Step 1: Write the failing test**

```dart
// test/app_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/data/settings_store.dart';

import 'support/fakes.dart'; // FakeProfileStore, FakeHistoryStore, FakeSettingsStore

void main() {
  testWidgets('app starts on the initialTheme', (tester) async {
    final settings = FakeSettingsStore();
    await tester.pumpWidget(MeowWatchApp(
      profiles: FakeProfileStore(),
      history: FakeHistoryStore(),
      settings: settings,
      initialTheme: MeowThemeId.noir,
    ));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.extension<MeowColors>(), MeowColors.noir);
  });
}
```

> If `test/support/fakes.dart` does not already export `FakeProfileStore`/`FakeHistoryStore`, reuse whatever fakes the existing connect/home tests use (search `test/` for `class Fake` / `mocktail` `Mock` setups) and add a tiny `FakeSettingsStore` that stores values in a `Map<String,String>`. If no shared fakes file exists, create `test/support/fakes.dart` with all three.

- [ ] **Step 2: Run the test, verify it fails**

Run: `$FLUTTER test test/app_theme_test.dart`
Expected: FAIL — `MeowWatchApp` has no `settings`/`initialTheme` params (compile error).

- [ ] **Step 3: Rewrite `lib/app.dart` as a StatefulWidget**

```dart
// lib/app.dart
import 'package:flutter/material.dart';

import 'core/connect/room_config.dart';
import 'core/data/settings_store.dart';
import 'core/data/stores.dart';
import 'core/theme/meow_context.dart';
import 'core/theme/meow_theme.dart';
import 'ui/connect/connect_screen.dart';
import 'ui/home_screen.dart';

class MeowWatchApp extends StatefulWidget {
  const MeowWatchApp({
    required this.profiles,
    required this.history,
    required this.settings,
    required this.initialTheme,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;
  final SettingsStore settings;
  final MeowThemeId initialTheme;

  @override
  State<MeowWatchApp> createState() => _MeowWatchAppState();
}

class _MeowWatchAppState extends State<MeowWatchApp> {
  late MeowThemeId _theme = widget.initialTheme;

  void _setTheme(MeowThemeId id) {
    if (id == _theme) return;
    setState(() => _theme = id);
    // Fire-and-forget persistence; UI already updated.
    widget.settings.set(kThemeSettingKey, id.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeowWatch',
      debugShowCheckedModeBanner: false,
      theme: themeDataFor(_theme),
      home: Builder(
        builder: (context) => ConnectScreen(
          profiles: widget.profiles,
          history: widget.history,
          currentTheme: _theme,
          onThemeChanged: _setTheme,
          onConnect: (RoomConfig config) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HomeScreen(
                config: config,
                history: widget.history,
                currentTheme: _theme,
                onThemeChanged: _setTheme,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the new constructor params to `ConnectScreen` and `HomeScreen`**

In `lib/ui/connect/connect_screen.dart`, add to the `ConnectScreen` constructor + fields:

```dart
    required this.currentTheme,
    required this.onThemeChanged,
```
```dart
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
```
and `import '../../core/theme/meow_theme.dart';`

In `lib/ui/home_screen.dart`, add to the `HomeScreen` constructor + fields the same two params and the same import. (They are consumed in Tasks 8–9; storing them now keeps the app compiling.)

- [ ] **Step 5: Update `lib/main.dart` to load the saved theme**

```dart
// lib/main.dart
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/data/app_database.dart';
import 'core/data/drift_stores.dart';
import 'core/data/settings_store.dart';
import 'core/theme/meow_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final db = await openAppDatabase();
  final settings = DriftSettingsStore(db);
  final savedTheme = MeowThemeId.fromName(await settings.get(kThemeSettingKey));

  runApp(MeowWatchApp(
    profiles: DriftProfileStore(db),
    history: DriftHistoryStore(db),
    settings: settings,
    initialTheme: savedTheme,
  ));
}
```

- [ ] **Step 6: Run the test + analyze**

Run: `$FLUTTER test test/app_theme_test.dart`
Expected: PASS.
Run: `$FLUTTER analyze`
Expected: may report pre-existing widget tests that construct `ConnectScreen`/`HomeScreen` without the new required params — fix those call sites by passing `currentTheme: MeowThemeId.cozy, onThemeChanged: (_) {}`. Re-run until "No issues found!".

- [ ] **Step 7: Commit**

```bash
git add lib/app.dart lib/main.dart lib/ui/connect/connect_screen.dart lib/ui/home_screen.dart test/app_theme_test.dart test/support/fakes.dart
git commit -m "feat: hold active theme at app root, load+persist via SettingsStore"
```

---

### Task 6: Refactor the standalone overlay widgets to `context.meow`

These five files have no `const` constructor entanglement beyond `const TextStyle` and are the simplest. For each: add `import '../core/theme/meow_context.dart';`, read `final m = context.meow;` at the top of `build`, replace literals per the **mapping table**, and remove `const` from any widget/`TextStyle`/`BoxDecoration` that now references `m`.

**Files:**
- Modify: `lib/ui/seek_indicator.dart` (literals at lines 23, 24, 72)
- Modify: `lib/ui/volume_indicator.dart` (lines 11, 12, 29, 44)
- Modify: `lib/ui/action_feedback_overlay.dart` (lines 74, 80)
- Modify: `lib/ui/empty_state.dart` (lines 11, 17, 21, 26, 27)
- Modify: `lib/ui/peek_tab.dart` → actually `lib/ui/chat/peek_tab.dart` (lines 20, 22, 26)

- [ ] **Step 1: Refactor each file**

For every literal, apply the mapping table. Concretely:
- `0xFFF5E6D3` → `m.textPrimary`
- `0xFFD4A574` → `m.accent`
- `0x99000000` → `m.scrim.withValues(alpha: 0.60)`
- `0x55F5E6D3` → `m.textPrimary.withValues(alpha: 0.33)`
- `0xFF1A1410` → `m.background`
- `0xCC1A1410` → `m.background.withValues(alpha: 0.80)`
- `0x55D4A574` → `m.border`

Example — `lib/ui/chat/peek_tab.dart` currently builds a tab with `Color(0xFFD4A574)`, `Color(0xCC1A1410)`, `Color(0x55D4A574)`, `Color(0xFFF5E6D3)`. After: at the start of `build`, `final m = context.meow;` then use `m.accent`, `m.background.withValues(alpha: 0.80)`, `m.border`, `m.textPrimary` respectively, dropping `const` on the affected `BoxDecoration`/`Text`/`Icon`.

> Mechanical rule: any widget literal you cannot keep `const` because it now reads `m` must have its `const` removed (and `const` removed from parents that included it). The analyzer will flag every leftover — use it as your checklist.

- [ ] **Step 2: Update the matching widget tests' pump harness**

Any test that pumps these widgets must wrap them so `context.meow` resolves. Find them: `test/ui/seek_indicator_test.dart`, `test/ui/volume_indicator_test.dart`, `test/ui/empty_state_test.dart`, `test/ui/chat/peek_tab_test.dart`, and any `action_feedback` test (search `test/ui` for the widget names). For each `pumpWidget`, ensure the widget is under a `MaterialApp(theme: themeDataFor(MeowThemeId.cozy), home: …)` (or `Theme(data: themeDataFor(MeowThemeId.cozy), child: …)` inside a `Directionality`/`MaterialApp`). Add `import 'package:meowwatch/core/theme/meow_context.dart';` and `import 'package:meowwatch/core/theme/meow_theme.dart';` to those tests.

- [ ] **Step 3: Run analyze + the affected tests**

Run: `$FLUTTER analyze`
Expected: "No issues found!" (fix any leftover `const`/undefined-`m` errors it lists).
Run: `$FLUTTER test test/ui/seek_indicator_test.dart test/ui/volume_indicator_test.dart test/ui/empty_state_test.dart test/ui/chat/peek_tab_test.dart`
Expected: PASS (Cozy values are byte-identical to before, so behavior is unchanged).

- [ ] **Step 4: Commit**

```bash
git add lib/ui/seek_indicator.dart lib/ui/volume_indicator.dart lib/ui/action_feedback_overlay.dart lib/ui/empty_state.dart lib/ui/chat/peek_tab.dart test/ui/
git commit -m "refactor: read overlay widget colors from context.meow"
```

---

### Task 7: Refactor the chat widgets (`chat_bubble`, `chat_input`, `chat_overlay`) + glass support

**Files:**
- Modify: `lib/ui/chat/chat_bubble.dart` (lines 31, 33, 46, 54, 62)
- Modify: `lib/ui/chat/chat_input.dart` (lines 40, 43, 46, 49, 52, 58)
- Modify: `lib/ui/chat/chat_overlay.dart` (lines 171, 185, 187, 204, 208, 213, 228)
- Test: existing chat tests + goldens

- [ ] **Step 1: Refactor `chat_bubble.dart`**

Replace the build body's colors. `final m = context.meow;` at the top of `build`. Mapping:
- own/peer fill (line 31): `_mine ? m.myBubble : m.peerBubble`
- border (line 33): `m.accent.withValues(alpha: 0.20)`
- sender name (line 46): `m.accent` — and apply the title font: `fontFamily: m.titleFontFamily` on that `TextStyle` (gives Noir its serif sender labels)
- message text (line 54): `m.textPrimary`
- timestamp (line 62): `m.textDim`

Remove `const` from each `TextStyle`/`BoxDecoration` that now references `m`.

- [ ] **Step 2: Refactor `chat_input.dart`**

`final m = context.meow;`. Mapping: `0xFFF5E6D3`→`m.textPrimary`; `0x66F5E6D3`→`m.textPrimary.withValues(alpha: 0.40)`; `0x55D4A574`→`m.border`; `0xFFD4A574`→`m.accent`. Strip `const` as needed.

- [ ] **Step 3: Refactor `chat_overlay.dart` + add glass**

`final m = context.meow;`. Mapping: `0x99000000`→`m.scrim.withValues(alpha: 0.60)`; `0xF2241B14`→`m.surface`; `0xCCD4A574`→`m.accent.withValues(alpha: 0.80)`; `0x99F5E6D3`→`m.textDim`; `0xFFF5E6D3`→`m.textPrimary`; `0xFFD4A574`→`m.accent`.

Then wrap the chat card's surface in a blur when `m.glassBlur > 0`. Find the `Container`/`DecoratedBox` that paints the card surface (the one using `0xF2241B14`) and wrap its child tree like:

```dart
import 'dart:ui' show ImageFilter;
// ...
Widget _frosted(BuildContext context, Widget child) {
  final blur = context.meow.glassBlur;
  if (blur <= 0) return child;
  return ClipRRect(
    borderRadius: BorderRadius.circular(16), // match the card's radius
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    ),
  );
}
```

Wrap the card surface container with `_frosted(context, …)`. (Keep the same `borderRadius` the card already uses.)

- [ ] **Step 4: Update chat test pump harnesses**

As in Task 6 Step 2: every chat widget test (`test/ui/chat/chat_bubble_test.dart`, `chat_input_test.dart`, `chat_overlay_*_test.dart`, golden tests) must pump under `MaterialApp(theme: themeDataFor(MeowThemeId.cozy), …)`. Add the two theme imports.

- [ ] **Step 5: Regenerate goldens and inspect**

Cozy is byte-identical, so goldens *should* be unchanged — but the harness now wraps in MaterialApp, which can shift layout slightly. Run the golden file(s):

Run: `$FLUTTER test test/ui/chat/chat_overlay_golden_test.dart`
- If it PASSES, good.
- If it FAILS only due to the harness wrapper (not a real visual regression), regenerate and eyeball:
  Run: `$FLUTTER test test/ui/chat/chat_overlay_golden_test.dart --update-goldens`
  Then open `test/ui/chat/goldens/*.png` and confirm it still looks like the Cozy chat card before committing.

- [ ] **Step 6: Run analyze + chat tests**

Run: `$FLUTTER analyze` → "No issues found!"
Run: `$FLUTTER test test/ui/chat/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/chat/ test/ui/chat/
git commit -m "refactor: theme chat widgets via context.meow + glass blur support"
```

---

### Task 8: Refactor `home_screen.dart` + `playback_bar.dart` + gradient background

**Files:**
- Modify: `lib/ui/home_screen.dart` (lines 298, 300, 304, 319, 322, 332, 335)
- Modify: `lib/ui/playback_bar.dart` (static consts at 19–20; literals at 36, 55)
- Test: `test/ui/playback_bar_test.dart`, home screen tests

- [ ] **Step 1: Refactor `playback_bar.dart`**

Delete the `static const _cream`/`_amber`. In `build`, add `final m = context.meow;` and `import 'package:meowwatch/core/theme/meow_context.dart';` (relative: `import '../core/theme/meow_context.dart';`). Replace:
- `_cream` → `m.textPrimary`
- `_amber` → `m.accent`
- `Color(0xCC000000)` → `m.scrim.withValues(alpha: 0.80)`
- `Color(0x00000000)` → `Colors.transparent`
- `Color(0x55F5E6D3)` (inactive track) → `m.textPrimary.withValues(alpha: 0.33)`

`SliderThemeData` is currently `const` — make it non-const (`SliderThemeData(...)`) since it now references `m`. The bottom gradient `BoxDecoration` becomes non-const too.

- [ ] **Step 2: Refactor `home_screen.dart` banners + gradient background**

`final m = context.meow;` near the top of `build`. Replace the banner/hint literals: `0xCC1A1410`→`m.background.withValues(alpha: 0.80)`; `0x55D4A574`→`m.border`; `0xFFF5E6D3`→`m.textPrimary`.

For the window background: find the root `Scaffold`/`Container` that fills behind the video. If the theme has a gradient, paint it. Add a small helper at the top of `build`:

```dart
final m = context.meow;
final bgDecoration = m.backgroundGradient != null
    ? BoxDecoration(gradient: m.backgroundGradient)
    : BoxDecoration(color: m.background);
```

Wrap the screen body in `DecoratedBox(decoration: bgDecoration, child: …)` (or set the `Scaffold` `backgroundColor: m.backgroundGradient == null ? m.background : Colors.transparent` and put a `Container(decoration: bgDecoration)` as the bottom Stack layer). Keep the existing video/controls/chat Stack on top.

- [ ] **Step 3: Update test harnesses**

`test/ui/playback_bar_test.dart` and any home-screen test that pumps these: wrap in `MaterialApp(theme: themeDataFor(MeowThemeId.cozy), …)` and add the theme imports. Home-screen tests already need the `currentTheme`/`onThemeChanged` params added in Task 5 — pass `MeowThemeId.cozy` / `(_) {}`.

- [ ] **Step 4: Run analyze + tests**

Run: `$FLUTTER analyze` → "No issues found!"
Run: `$FLUTTER test test/ui/playback_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home_screen.dart lib/ui/playback_bar.dart test/ui/
git commit -m "refactor: theme home screen + playback bar, paint gradient background"
```

---

### Task 9: Connect-screen swatch switcher

**Files:**
- Create: `lib/ui/theme/theme_swatches.dart`
- Modify: `lib/ui/connect/connect_screen.dart`
- Test: `test/ui/theme/theme_swatches_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/theme/theme_swatches_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/theme/theme_swatches.dart';

void main() {
  testWidgets('tapping a swatch fires onChanged with that id', (tester) async {
    MeowThemeId? picked;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ThemeSwatches(
          current: MeowThemeId.cozy,
          onChanged: (id) => picked = id,
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('theme-swatch-noir')));
    expect(picked, MeowThemeId.noir);
  });

  testWidgets('renders one swatch per preset', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ThemeSwatches(current: MeowThemeId.cozy, onChanged: (_) {}),
      ),
    ));
    for (final id in MeowThemeId.values) {
      expect(find.byKey(Key('theme-swatch-${id.name}')), findsOneWidget);
    }
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$FLUTTER test test/ui/theme/theme_swatches_test.dart`
Expected: FAIL — `ThemeSwatches` undefined.

- [ ] **Step 3: Implement `theme_swatches.dart`**

```dart
// lib/ui/theme/theme_swatches.dart
import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_theme.dart';

/// A row of tappable color chips, one per theme preset. The active one shows a
/// ring. Tapping fires [onChanged].
class ThemeSwatches extends StatelessWidget {
  const ThemeSwatches({
    required this.current,
    required this.onChanged,
    super.key,
  });

  final MeowThemeId current;
  final ValueChanged<MeowThemeId> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (final id in MeowThemeId.values)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              key: Key('theme-swatch-${id.name}'),
              onTap: () => onChanged(id),
              child: Tooltip(
                message: id.label,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: id.colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: id == current ? m.textPrimary : m.border,
                      width: id == current ? 2.5 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Embed in the Connect screen**

In `lib/ui/connect/connect_screen.dart`, add `import '../theme/theme_swatches.dart';`. Inside the `Column` in `build` (after the "Watch together, in sync." subtitle, before the `SizedBox(height: 24)` that precedes "Your name"), insert:

```dart
                    const SizedBox(height: 16),
                    _label('Theme'),
                    ThemeSwatches(
                      current: widget.currentTheme,
                      onChanged: widget.onThemeChanged,
                    ),
```

(Also complete the Task 6/7 mapping refactor of the module-level `const _bg/_card/_amber/_cream/_dim/_border` in this file: convert them to `context.meow` reads inside `build`/helpers, since this file is one of the 12. The helpers `_label`/`_textField`/`_profileCard` take `BuildContext` — they already have access via the `StatefulWidget`'s `context`. Replace `_bg`→`m.background`, `_card`→`m.surface`, `_amber`→`m.accent`, `_cream`→`m.textPrimary`, `_dim`→`m.textDim`, `_border`→`m.border`, and the green dot `0xFF7BC47F`→`m.online`. Strip `const` from the affected `Text`/`TextStyle`/`Card`/`BorderSide`. The `_ContinueWatching` widget also uses these consts — give it `final m = context.meow;` in its `build` and the same swaps.)

- [ ] **Step 5: Update connect-screen test harness**

`test/ui/connect/connect_screen_test.dart` (and any connect tests): pump under `MaterialApp(theme: themeDataFor(MeowThemeId.cozy), …)`, pass the new `currentTheme`/`onThemeChanged` params, add theme imports.

- [ ] **Step 6: Run analyze + tests**

Run: `$FLUTTER analyze` → "No issues found!"
Run: `$FLUTTER test test/ui/theme/theme_swatches_test.dart test/ui/connect/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/theme/theme_swatches.dart lib/ui/connect/connect_screen.dart test/ui/theme/ test/ui/connect/
git commit -m "feat: theme swatches on the Connect screen + finish connect refactor"
```

---

### Task 10: In-watch theme toggle in the control bar

**Files:**
- Modify: `lib/ui/playback_bar.dart` (add a theme button)
- Modify: `lib/ui/home_screen.dart` (pass theme + callback into the bar)
- Test: `test/ui/playback_bar_test.dart`

The control bar (`PlaybackBar`) is the in-watch surface. Add an optional theme button that cycles to the next preset, so the user sees the change live over the video.

- [ ] **Step 1: Write the failing test**

```dart
// add to test/ui/playback_bar_test.dart
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
// ...
  testWidgets('theme button cycles to the next preset', (tester) async {
    MeowThemeId? next;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          state: /* a minimal PlaybackState — reuse the helper other tests use */ samplePlaybackState(),
          onSeek: (_) {},
          onTogglePlay: () {},
          currentTheme: MeowThemeId.cozy,
          onThemeChanged: (id) => next = id,
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('playback-theme-toggle')));
    expect(next, MeowThemeId.noir); // cozy -> noir -> aurora -> cozy
  });
```

> Use the same `PlaybackState` construction the existing `playback_bar_test.dart` already uses (search the file for how it builds `state`); the `samplePlaybackState()` above is a stand-in for that existing pattern.

- [ ] **Step 2: Run the test, verify it fails**

Run: `$FLUTTER test test/ui/playback_bar_test.dart -p "theme button cycles"`
Expected: FAIL — `PlaybackBar` has no `currentTheme`/`onThemeChanged` params.

- [ ] **Step 3: Add the params + button to `PlaybackBar`**

Add to the constructor (make them optional so existing call sites/tests that don't pass them still compile — but Home will pass them):

```dart
    this.currentTheme,
    this.onThemeChanged,
```
```dart
  final MeowThemeId? currentTheme;
  final ValueChanged<MeowThemeId>? onThemeChanged;
```
Add the import `import '../core/theme/meow_theme.dart';`. In the `Row` of `build`, after the trailing duration `Text`, add (only when wired):

```dart
          if (currentTheme != null && onThemeChanged != null)
            IconButton(
              key: const Key('playback-theme-toggle'),
              tooltip: 'Theme',
              icon: Icon(Icons.palette_outlined, color: m.textPrimary),
              onPressed: () {
                final ids = MeowThemeId.values;
                final next = ids[(currentTheme!.index + 1) % ids.length];
                onThemeChanged!(next);
              },
            ),
```

- [ ] **Step 4: Pass theme into the bar from `home_screen.dart`**

Where `HomeScreen` builds the `PlaybackBar`, pass `currentTheme: widget.currentTheme, onThemeChanged: widget.onThemeChanged,`.

- [ ] **Step 5: Run analyze + tests**

Run: `$FLUTTER analyze` → "No issues found!"
Run: `$FLUTTER test test/ui/playback_bar_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/playback_bar.dart lib/ui/home_screen.dart test/ui/playback_bar_test.dart
git commit -m "feat: in-watch theme toggle in the control bar"
```

---

### Task 11: Full-suite green + zero-literal verification

**Files:** none (verification only)

- [ ] **Step 1: Confirm no stray ARGB literals remain in widget files**

Run (PowerShell-safe via Grep tool, or):
`$FLUTTER analyze`
Then search the codebase for any remaining 8-digit hex in `lib/ui/` and `lib/app.dart` — the only acceptable matches are inside `lib/core/theme/meow_theme.dart` (the presets). If any remain in a widget, map them via the table and replace.

Expected: the only `0x........` occurrences are in `lib/core/theme/meow_theme.dart`.

- [ ] **Step 2: Run the full suite**

Run: `$FLUTTER test`
Expected: ALL pass (previous count was 119; new theme/settings/swatch tests add to it). Investigate any failure before proceeding.

- [ ] **Step 3: Run analyze once more**

Run: `$FLUTTER analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit (if any cleanup was needed)**

```bash
git add -A
git commit -m "chore: phase 5 theme refactor cleanup — no hardcoded colors outside presets"
```

---

### Task 12: Manual verification (Release) + tag

**Files:** `docs/ROADMAP.md`, memory (post-confirmation)

> Per CLAUDE.md: kill any running `meowwatch.exe` before building (file lock), and verify the change landed by checking `build/windows/x64/runner/Release/data/app.so` mtime (not the `.exe`). Manual test MUST use the Release build.

- [ ] **Step 1: Build Release**

```bash
# Kill running instances first (PowerShell): Stop-Process -Name meowwatch -Force  (ignore if none)
$FLUTTER build windows
```
Expected: "Built build\windows\x64\runner\Release\meowwatch.exe". Confirm `…\Release\data\app.so` mtime is now.

- [ ] **Step 2: Ask the user to run the manual checklist**

Launch `build/windows/x64/runner/Release/meowwatch.exe` and confirm:
1. Default theme is **Cozy** and looks identical to before.
2. On the Connect screen, tap the **Noir** swatch → black/gold + serif chat/sender text applies immediately.
3. Enter a room, tap the control-bar **theme button** → cycles to **Aurora** → violet→cyan gradient background + frosted-glass chat card/control bar apply live.
4. Close the app and relaunch → the last chosen theme is restored.

Do NOT tag complete until the user confirms this passes.

- [ ] **Step 3: After user confirmation — update ROADMAP + tag**

Edit `docs/ROADMAP.md` Phase 5 row to `5 ✅ ... **Shipped (tag `phase-5-complete`).**` with a one-line description and the plan link, then:

```bash
git add docs/ROADMAP.md
git commit -m "docs: mark Phase 5 themes shipped"
git tag phase-5-complete
```

- [ ] **Step 4: Update project memory**

Add a "Phase 5 SHIPPED" bullet to `the agent project memory file` (theme system: MeowColors ThemeExtension + 3 presets, Settings table v1→v2 migration, switcher on Connect + control bar, context.meow getter, zero hardcoded colors outside presets) and note any new gotcha discovered (e.g. golden harness needing a themed wrapper).
