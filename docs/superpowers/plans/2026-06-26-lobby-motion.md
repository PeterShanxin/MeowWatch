# Lobby Motion (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the in-app Reduce-motion switch plus three lobby motions — a cold-start card cascade, a fade-up room transition, and reduce-motion-aware polish of the theme cross-fade and gear popover — shipping as 0.37.0-alpha.

**Architecture:** Build on the Phase 1 foundation (`Motion.*` tokens, `RevealIn`, `ReduceMotionScope` + `context.reduceMotion`, `StaggeredReflowList`). A new app-level setting flows like the existing `theme` setting (loaded in `main`, owned by `MeowWatchApp`, injected app-wide via a `ReduceMotionScope` and threaded to both settings gears). Two small new primitives — `fadeUpRoute` and `StaggeredReveal` — deliver the room transition and the card cascade; both degrade to instant via `context.reduceMotion`. `StaggeredReflowList` is not modified.

**Tech Stack:** Flutter desktop (Windows-first), Dart, `AnimationController`/`PageRouteBuilder`/`MaterialApp.themeAnimationDuration`, the Phase 1 `RevealIn`.

**Source of truth:** `docs/superpowers/specs/2026-06-26-lobby-motion-design.md`.

## Global Constraints

- **Toolchain (NOT on PATH):** `FLUTTER=C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`. Run `$FLUTTER analyze` (keep "No issues found!") and `$FLUTTER test` locally — never defer to CI.
- **TDD:** RED → GREEN → REFACTOR. Small conventional-commit (`feat:` / `test:` / `refactor:` / `chore:`) checkpoints at each verified step.
- **Versioning (lockstep, this PR is one MINOR bump):** `pubspec.yaml` `version:` → `0.37.0-alpha+1`, `lib/core/app_version.dart` `appVersion` → `'0.37.0-alpha'`, and a new top `## [0.37.0-alpha] - 2026-06-26` entry in `CHANGELOG.md`. Keep the `-alpha` suffix.
- **Reduce-motion default = off.** OS "reduce animations" forces it on independently (`context.reduceMotion` ORs the app scope with `MediaQuery.disableAnimationsOf`).
- **New widget params are optional** (`bool` defaults `false`; callbacks are nullable, called as `cb ?? (_) {}`) so existing test helpers keep compiling.
- **Immutability / file size:** new objects over mutation; keep new files focused (200–400 lines typical).
- **Don't touch `StaggeredReflowList`** — the cascade wraps card widgets from the outside.
- **Manual-test build:** kill the build-output `meowwatch.exe` (`D:\Repos\MeowWatch\build\windows\x64\runner\Release\meowwatch.exe`) before `flutter build windows` — never blanket-kill (the user co-watches on a separate copy).

---

### Task 1: Reduce-motion setting — app state, scope, persistence, startup load

**Files:**
- Modify: `lib/core/data/settings_store.dart`
- Modify: `lib/app.dart`
- Modify: `lib/main.dart`
- Test: `test/app_reduce_motion_test.dart` (create)

**Interfaces:**
- Consumes: `ReduceMotionScope` (`lib/core/theme/reduce_motion.dart`), `SettingsStore` (`lib/core/data/settings_store.dart`).
- Produces:
  - `const String kReduceMotionSettingKey = 'reduce_motion';`
  - `MeowWatchApp({..., bool initialReduceMotion = false})`, with `_reduceMotion` state and `void _setReduceMotion(bool value)` (parallel to `_theme`/`_setTheme`), and an app-wide `ReduceMotionScope` injected via `MaterialApp.builder`. Consumed by Tasks 2, 4, 5.

- [ ] **Step 1: Write the failing test**

Create `test/app_reduce_motion_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';

import 'support/fakes.dart';

void main() {
  Widget app({required bool reduceMotion}) => MeowWatchApp(
        profiles: FakeProfileStore(),
        history: FakeHistoryStore(),
        settings: FakeSettingsStore(),
        initialTheme: MeowThemeId.cozy,
        initialReduceMotion: reduceMotion,
        showLaunchReveal: true,
      );

  testWidgets('the reduce-motion setting flows into context.reduceMotion '
      '(launch splash is skipped)', (tester) async {
    await tester.pumpWidget(app(reduceMotion: true));
    await tester.pump(); // post-frame complete
    expect(find.byKey(const Key('launch-reveal-splash')), findsNothing);
  });

  testWidgets('with the setting off, the launch splash plays', (tester) async {
    await tester.pumpWidget(app(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('launch-reveal-splash')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900)); // settle for teardown
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/app_reduce_motion_test.dart`
Expected: FAIL — `initialReduceMotion` is not a parameter of `MeowWatchApp`.

- [ ] **Step 3: Add the settings key**

In `lib/core/data/settings_store.dart`, add after the `kHistoryModeSettingKey` block:

```dart
/// Key for the persisted in-app "reduce motion" choice (value = "true"/"false",
/// absent/default → "false"). When on, every app motion degrades to an instant
/// present; the OS "reduce animations" setting forces the same independently.
const String kReduceMotionSettingKey = 'reduce_motion';
```

- [ ] **Step 4: Wire app state + the app-wide scope**

In `lib/app.dart`, add the import near the other `core/theme` imports:

```dart
import 'core/theme/reduce_motion.dart';
```

Add the constructor parameter (before `super.key,`) and field:

```dart
    this.initialReduceMotion = false,
```

```dart
  /// Whether app motion starts reduced (the persisted in-app switch). The OS
  /// "reduce animations" setting forces the same independently of this.
  final bool initialReduceMotion;
```

In `_MeowWatchAppState`, add the state + setter next to `_theme`/`_setTheme`:

```dart
  late bool _reduceMotion = widget.initialReduceMotion;

  void _setReduceMotion(bool value) {
    if (value == _reduceMotion) return;
    setState(() => _reduceMotion = value);
    // Fire-and-forget persistence; UI already updated.
    widget.settings.set(kReduceMotionSettingKey, value ? 'true' : 'false');
  }
```

Inject the scope above every route via `MaterialApp.builder`. In the `MaterialApp(...)`, add right after `theme: themeDataFor(_theme),`:

```dart
      builder: (context, child) => ReduceMotionScope(
        reduceMotion: _reduceMotion,
        child: child!,
      ),
```

- [ ] **Step 5: Load it at startup**

In `lib/main.dart`, after the `savedTheme` line (`final savedTheme = MeowThemeId.fromName(...)`), add:

```dart
  final reduceMotion =
      (await settings.get(kReduceMotionSettingKey)) == 'true';
```

In the `runApp(MeowWatchApp(...))` call, add after `initialTheme: savedTheme,`:

```dart
    initialReduceMotion: reduceMotion,
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/app_reduce_motion_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Analyze + commit**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

```bash
git add lib/core/data/settings_store.dart lib/app.dart lib/main.dart test/app_reduce_motion_test.dart
git commit -m "feat: add reduce-motion setting + app-wide ReduceMotionScope"
```

---

### Task 2: Reduce-motion toggle control + thread it through both gears

**Files:**
- Modify: `lib/ui/settings/settings_panel.dart`
- Modify: `lib/ui/settings/lobby_settings_button.dart`
- Modify: `lib/ui/connect/connect_screen.dart`
- Modify: `lib/ui/player_menu_button.dart`
- Modify: `lib/ui/home_screen.dart`
- Modify: `lib/app.dart`
- Test: `test/ui/settings/reduce_motion_control_test.dart` (create)

**Interfaces:**
- Consumes: `_setReduceMotion` / `_reduceMotion` (Task 1).
- Produces: `class ReduceMotionControl extends StatelessWidget { const ReduceMotionControl({required bool value, required ValueChanged<bool> onChanged, Key? key}); }`; and optional `reduceMotion` + `onReduceMotionChanged` params on `SettingsPanel`, `LobbySettingsButton`, `PlayerMenuButton`, `ConnectScreen`, `HomeScreen`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/settings/reduce_motion_control_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/settings/settings_panel.dart';

void main() {
  testWidgets('reflects value and fires onChanged on tap', (tester) async {
    bool? picked;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ReduceMotionControl(value: false, onChanged: (v) => picked = v),
      ),
    ));
    await tester.tap(find.byKey(const Key('reduce-motion-on')));
    expect(picked, isTrue);

    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: ReduceMotionControl(value: true, onChanged: (v) => picked = v),
      ),
    ));
    await tester.tap(find.byKey(const Key('reduce-motion-off')));
    expect(picked, isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/settings/reduce_motion_control_test.dart`
Expected: FAIL — `ReduceMotionControl` is undefined.

- [ ] **Step 3: Add `ReduceMotionControl` + the panel row**

In `lib/ui/settings/settings_panel.dart`, add this class after `HistoryModeControl` (it reuses the file-private `_LogLevelSegment`):

```dart
/// Two-way On/Off control for the in-app "reduce motion" setting, shown as a
/// labelled segmented row matching [HistoryModeControl]. Picking a segment fires
/// [onChanged]. Public so it can be unit-tested directly.
class ReduceMotionControl extends StatelessWidget {
  const ReduceMotionControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reduce motion',
            style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: Spacing.xs),
                  child: _LogLevelSegment(
                    key: const Key('reduce-motion-off'),
                    text: 'Off',
                    selected: !value,
                    onTap: () => onChanged(false),
                  ),
                ),
              ),
              Expanded(
                child: _LogLevelSegment(
                  key: const Key('reduce-motion-on'),
                  text: 'On',
                  selected: value,
                  onTap: () => onChanged(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

Add the two optional params to `SettingsPanel`'s constructor (before `super.key,`):

```dart
    this.reduceMotion = false,
    this.onReduceMotionChanged,
```

and the field declarations (with the other finals):

```dart
  final bool reduceMotion;
  final ValueChanged<bool>? onReduceMotionChanged;
```

In `SettingsPanel.build`, prepend the row + a divider as the first children of the `Column` (before `HistoryModeControl(...)`):

```dart
        ReduceMotionControl(
          value: reduceMotion,
          onChanged: onReduceMotionChanged ?? (_) {},
        ),
        Divider(color: m.border, height: Spacing.lg),
```

- [ ] **Step 4: Run the control test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/settings/reduce_motion_control_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Thread it through the lobby gear**

In `lib/ui/settings/lobby_settings_button.dart`, add the two optional params to `LobbySettingsButton`'s constructor (before `super.key,`):

```dart
    this.reduceMotion = false,
    this.onReduceMotionChanged,
```

and the fields:

```dart
  final bool reduceMotion;
  final ValueChanged<bool>? onReduceMotionChanged;
```

In `_panel(...)`, where it builds `SettingsPanel(...)`, add after `historyMode: widget.historyMode,`:

```dart
                reduceMotion: widget.reduceMotion,
                onReduceMotionChanged: widget.onReduceMotionChanged,
```

- [ ] **Step 6: Thread it through `ConnectScreen` → app**

In `lib/ui/connect/connect_screen.dart`, add the two optional params to `ConnectScreen`'s constructor (before `super.key,`):

```dart
    this.reduceMotion = false,
    this.onReduceMotionChanged,
```

and the fields:

```dart
  final bool reduceMotion;
  final ValueChanged<bool>? onReduceMotionChanged;
```

In `build`, where it constructs `LobbySettingsButton(...)`, add after `historyMode: _historyMode,`:

```dart
              reduceMotion: widget.reduceMotion,
              onReduceMotionChanged: widget.onReduceMotionChanged,
```

In `lib/app.dart`, where the `home:` builder constructs `ConnectScreen(...)`, add after `settings: widget.settings,`:

```dart
            reduceMotion: _reduceMotion,
            onReduceMotionChanged: _setReduceMotion,
```

- [ ] **Step 7: Thread it through the in-room gear**

In `lib/ui/player_menu_button.dart`, add the two optional params to **both** `PlayerMenuButton`'s and `_MenuPanel`'s constructors (before `super.key,` / before the closing `});`):

```dart
    this.reduceMotion = false,
    this.onReduceMotionChanged,
```

and the matching fields in **both** classes:

```dart
  final bool reduceMotion;
  final ValueChanged<bool>? onReduceMotionChanged;
```

In `PlayerMenuButton.build`, where it constructs `_MenuPanel(...)`, add after `historyMode: historyMode,`:

```dart
            reduceMotion: reduceMotion,
            onReduceMotionChanged: onReduceMotionChanged,
```

In `_MenuPanelState.build`, where it constructs `SettingsPanel(...)`, add after `historyMode: widget.historyMode,`:

```dart
                          reduceMotion: widget.reduceMotion,
                          onReduceMotionChanged: widget.onReduceMotionChanged,
```

- [ ] **Step 8: Thread it through `HomeScreen` → app**

In `lib/ui/home_screen.dart`, add the two optional params to `HomeScreen`'s constructor (before `super.key,`):

```dart
    this.reduceMotion = false,
    this.onReduceMotionChanged,
```

and the fields (next to `currentTheme` / `onThemeChanged`):

```dart
  final bool reduceMotion;
  final ValueChanged<bool>? onReduceMotionChanged;
```

In `home_screen.dart`, where it builds `PlayerMenuButton(...)` (around line 1559), add after `currentTheme: widget.currentTheme,`:

```dart
                            reduceMotion: widget.reduceMotion,
                            onReduceMotionChanged: widget.onReduceMotionChanged,
```

In `lib/app.dart`, where `onConnect` constructs `HomeScreen(...)`, add after `currentTheme: _theme,`:

```dart
                  reduceMotion: _reduceMotion,
                  onReduceMotionChanged: _setReduceMotion,
```

- [ ] **Step 9: Verify the touched suites + analyze**

Run:
```
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/settings/reduce_motion_control_test.dart test/ui/settings/settings_panel_test.dart test/ui/settings/lobby_settings_button_test.dart test/ui/player_menu_button_test.dart test/ui/connect/connect_screen_test.dart
```
Expected: `No issues found!` and all green (the optional params keep the existing helpers compiling; the new panel row doesn't break their assertions).

- [ ] **Step 10: Commit**

```bash
git add lib/ui/settings/settings_panel.dart lib/ui/settings/lobby_settings_button.dart lib/ui/connect/connect_screen.dart lib/ui/player_menu_button.dart lib/ui/home_screen.dart lib/app.dart test/ui/settings/reduce_motion_control_test.dart
git commit -m "feat: add Reduce motion toggle to the lobby + in-room gear"
```

---

### Task 3: Fade-up room transition

**Files:**
- Create: `lib/ui/motion/fade_up_route.dart`
- Modify: `lib/app.dart`
- Test: `test/ui/motion/fade_up_route_test.dart` (create)

**Interfaces:**
- Consumes: `Motion.slow` / `Motion.base` / `Motion.emphasized` (`lib/core/theme/tokens/motion.dart`).
- Produces: `PageRouteBuilder<T> fadeUpRoute<T>({required Widget page, required bool reduceMotion})`. Consumed by `app.dart`'s `onConnect`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/motion/fade_up_route_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/motion/fade_up_route.dart';

void main() {
  testWidgets('fades + slides the page in and reverses on pop', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('lobby')),
    ));

    navKey.currentState!.push(fadeUpRoute<void>(
      reduceMotion: false,
      page: const Scaffold(body: Text('room')),
    ));
    await tester.pump(); // start the transition
    await tester.pump(const Duration(milliseconds: 50)); // mid-transition
    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.byType(FadeTransition), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('room'), findsOneWidget);

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('lobby'), findsOneWidget);
  });

  testWidgets('reduce motion is an instant cut', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('lobby')),
    ));

    navKey.currentState!.push(fadeUpRoute<void>(
      reduceMotion: true,
      page: const Scaffold(body: Text('room')),
    ));
    await tester.pump();
    await tester.pump(); // no timed transition to wait on
    expect(find.text('room'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/motion/fade_up_route_test.dart`
Expected: FAIL — `fade_up_route.dart` does not exist.

- [ ] **Step 3: Create the route**

Create `lib/ui/motion/fade_up_route.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/theme/tokens/motion.dart';

/// A forward page push that fades [page] in while it rises from slightly below,
/// on the [Motion.emphasized] curve; reversed on pop. When [reduceMotion] is
/// true the transition is an instant cut (no fade, no rise) — pass
/// `context.reduceMotion` at the push site.
///
/// The rise uses a small fractional slide (4% of the page height) so it reads as
/// a gentle lift at any window size without per-pixel math.
PageRouteBuilder<T> fadeUpRoute<T>({
  required Widget page,
  required bool reduceMotion,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotion ? Duration.zero : Motion.slow,
    reverseTransitionDuration: reduceMotion ? Duration.zero : Motion.base,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final t = animation.drive(CurveTween(curve: Motion.emphasized));
      return FadeTransition(
        opacity: t,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(t),
          child: child,
        ),
      );
    },
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/motion/fade_up_route_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Use it for lobby → room**

In `lib/app.dart`, add the import near the other `ui/` imports:

```dart
import 'ui/motion/fade_up_route.dart';
```

In the `onConnect` callback, replace the `Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HomeScreen(...)))` with `fadeUpRoute`. The full replacement:

```dart
            onConnect: (RoomConfig config) => Navigator.of(context).push(
              fadeUpRoute<void>(
                reduceMotion: context.reduceMotion,
                page: HomeScreen(
                  config: config,
                  history: widget.history,
                  settings: widget.settings,
                  initialWidthPx: widget.initialCardWidthPx,
                  initialHeightPx: widget.initialCardHeightPx,
                  currentTheme: _theme,
                  onThemeChanged: _setTheme,
                  reduceMotion: _reduceMotion,
                  onReduceMotionChanged: _setReduceMotion,
                ),
              ),
            ),
```

(`context.reduceMotion` comes from the `reduce_motion.dart` import added in Task 1; the `Builder`'s context sits under the `MaterialApp.builder` scope. The `reduceMotion` / `onReduceMotionChanged` args on `HomeScreen` were added in Task 2.)

- [ ] **Step 6: Verify app-level suites + analyze**

Run:
```
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/motion/fade_up_route_test.dart test/app_launch_reveal_test.dart test/app_theme_test.dart
```
Expected: `No issues found!` and green.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/motion/fade_up_route.dart lib/app.dart test/ui/motion/fade_up_route_test.dart
git commit -m "feat: fade-up transition into a room (reduce-motion aware)"
```

---

### Task 4: Card cascade after the splash (cold start only)

**Files:**
- Create: `lib/ui/motion/staggered_reveal.dart`
- Modify: `lib/ui/connect/connect_screen.dart`
- Modify: `lib/app.dart`
- Test: `test/ui/motion/staggered_reveal_test.dart` (create)

**Interfaces:**
- Consumes: `RevealIn` (`lib/ui/motion/reveal_in.dart`), `Motion.stagger` / `Motion.base` (`lib/core/theme/tokens/motion.dart`), `context.reduceMotion`.
- Produces: `class StaggeredReveal extends StatefulWidget { const StaggeredReveal({required bool play, required List<Widget> children, bool holdHidden, Duration stagger, Duration itemDuration, double offset, CrossAxisAlignment crossAxisAlignment, Key? key}); }`; and optional `playLibraryEntrance` + `holdLibraryHidden` params on `ConnectScreen`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/motion/staggered_reveal_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/motion/staggered_reveal.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(home: Scaffold(body: child)),
    );

double _firstOpacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byType(Opacity).first).opacity;

void main() {
  testWidgets('held hidden until play, then cascades to fully present',
      (tester) async {
    await tester.pumpWidget(_host(const StaggeredReveal(
      play: false,
      holdHidden: true,
      children: [Text('a'), Text('b')],
    )));
    // Held invisible while the (simulated) reveal still covers it.
    expect(_firstOpacity(tester), 0);

    await tester.pumpWidget(_host(const StaggeredReveal(
      play: true,
      holdHidden: false,
      children: [Text('a'), Text('b')],
    )));
    await tester.pump(); // kick the RevealIns
    await tester.pump(const Duration(milliseconds: 500)); // settle the cascade
    final opacities =
        tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity);
    expect(opacities.every((o) => o == 1.0), isTrue);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('reduce motion shows children present instantly (no hidden hold)',
      (tester) async {
    await tester.pumpWidget(_host(
      const StaggeredReveal(
        play: false,
        holdHidden: true,
        children: [Text('a')],
      ),
      reduceMotion: true,
    ));
    await tester.pump();
    expect(find.text('a'), findsOneWidget);
    final anyHidden = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .any((o) => o.opacity == 0);
    expect(anyHidden, isFalse);
  });

  testWidgets('no-reveal case shows children present, no cascade',
      (tester) async {
    await tester.pumpWidget(_host(const StaggeredReveal(
      play: false,
      holdHidden: false,
      children: [Text('a')],
    )));
    await tester.pump();
    expect(find.text('a'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/motion/staggered_reveal_test.dart`
Expected: FAIL — `staggered_reveal.dart` does not exist.

- [ ] **Step 3: Create the cascade helper**

Create `lib/ui/motion/staggered_reveal.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/motion.dart';
import 'reveal_in.dart';

/// A one-shot, top-to-bottom entrance cascade for a column of [children].
///
/// When [play] turns true it ripples each child in with a staggered [RevealIn]
/// (fade + small rise), once. Before [play] the children are either held
/// invisible ([holdHidden] true — used while the launch reveal still covers
/// them, so the cascade reads as a clean *second* beat) or shown present
/// ([holdHidden] false — the no-reveal case: tests, or returning to the lobby).
/// Reduce motion shows every child present instantly, ignoring [play].
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    required this.play,
    required this.children,
    this.holdHidden = false,
    this.stagger = Motion.stagger,
    this.itemDuration = Motion.base,
    this.offset = 12,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    super.key,
  });

  final bool play;
  final bool holdHidden;
  final List<Widget> children;
  final Duration stagger;
  final Duration itemDuration;
  final double offset;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _started = widget.play;
  }

  @override
  void didUpdateWidget(StaggeredReveal old) {
    super.didUpdateWidget(old);
    // Latch on the rising edge of [play]; the framework rebuilds us right after.
    if (!_started && widget.play) _started = true;
  }

  Widget _column(List<Widget> children) => Column(
        crossAxisAlignment: widget.crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );

  @override
  Widget build(BuildContext context) {
    // Present instantly: reduce motion, or not-yet-playing in the no-reveal case.
    if (context.reduceMotion || (!_started && !widget.holdHidden)) {
      return _column(widget.children);
    }
    // Held invisible (keeps layout) until the cascade starts.
    if (!_started) {
      return Opacity(opacity: 0, child: _column(widget.children));
    }
    // The cascade: each child ripples in, staggered top-to-bottom.
    return _column([
      for (var i = 0; i < widget.children.length; i++)
        RevealIn(
          delay: widget.stagger * i,
          offset: widget.offset,
          duration: widget.itemDuration,
          child: widget.children[i],
        ),
    ]);
  }
}
```

- [ ] **Step 4: Run the helper test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/motion/staggered_reveal_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Wrap the lobby library column**

In `lib/ui/connect/connect_screen.dart`, add the import near the other `../` imports:

```dart
import '../motion/staggered_reveal.dart';
```

Add the two optional params to `ConnectScreen`'s constructor (before `super.key,`):

```dart
    this.playLibraryEntrance = false,
    this.holdLibraryHidden = false,
```

and the fields:

```dart
  /// Cold-start card cascade signals, driven by the launch reveal completing.
  /// [playLibraryEntrance] starts the one-shot ripple; [holdLibraryHidden] keeps
  /// the library invisible until then so it doesn't flash during the reveal.
  final bool playLibraryEntrance;
  final bool holdLibraryHidden;
```

In `build`, wrap the library widgets in `StaggeredReveal`. In the **two-column** branch, replace the right column:

```dart
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: _libraryColumn(
                                              savedProfiles,
                                              mostRecent,
                                            ),
                                          ),
                                        ),
```

with:

```dart
                                        Expanded(
                                          child: StaggeredReveal(
                                            play: widget.playLibraryEntrance,
                                            holdHidden: widget.holdLibraryHidden,
                                            children: _libraryColumn(
                                              savedProfiles,
                                              mostRecent,
                                            ),
                                          ),
                                        ),
```

In the **single-column** branch, replace the spread `..._libraryColumn(savedProfiles, mostRecent,)` with a wrapped child:

```dart
                                        StaggeredReveal(
                                          play: widget.playLibraryEntrance,
                                          holdHidden: widget.holdLibraryHidden,
                                          children: _libraryColumn(
                                            savedProfiles,
                                            mostRecent,
                                          ),
                                        ),
```

- [ ] **Step 6: Drive the signals from the launch reveal**

In `lib/app.dart`, add the reveal-settled state to `_MeowWatchAppState` (next to `_whatsNewShown`):

```dart
  bool _revealSettled = false;
```

Replace `_onRevealComplete` so it flips the cascade signal before the What's-new logic:

```dart
  void _onRevealComplete() {
    if (!_revealSettled) setState(() => _revealSettled = true);
    if (_whatsNewShown) return;
    _whatsNewShown = true;
    final entries = widget.whatsNewEntries;
    if (!widget.showWhatsNew || entries.isEmpty) return;
    final context = _navKey.currentContext;
    if (context != null) WhatsNewDialog.show(context, entries);
  }
```

Pass the signals to `ConnectScreen` — add after the `onReduceMotionChanged: _setReduceMotion,` line added in Task 2:

```dart
            playLibraryEntrance: widget.showLaunchReveal && _revealSettled,
            holdLibraryHidden: widget.showLaunchReveal && !_revealSettled,
```

- [ ] **Step 7: Verify the app + connect suites + analyze**

Run:
```
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/motion/staggered_reveal_test.dart test/app_launch_reveal_test.dart test/ui/connect/connect_screen_test.dart
```
Expected: `No issues found!` and green. (`connect_screen_test` builds `ConnectScreen` with the defaults `playLibraryEntrance: false, holdLibraryHidden: false` → library present, no cascade, assertions unchanged.)

- [ ] **Step 8: Commit**

```bash
git add lib/ui/motion/staggered_reveal.dart lib/ui/connect/connect_screen.dart lib/app.dart test/ui/motion/staggered_reveal_test.dart
git commit -m "feat: cascade the lobby cards in after the launch reveal"
```

---

### Task 5: Polish — instant theme swap + emphasized gear, both reduce-motion aware

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/ui/settings/lobby_settings_button.dart`
- Modify: `lib/ui/player_menu_button.dart`
- Test: `test/app_reduce_motion_test.dart` (append)

**Interfaces:**
- Consumes: `_reduceMotion` (Task 1), `context.reduceMotion`, `Motion.emphasized`.
- Produces: no new public API — `MaterialApp.themeAnimationDuration` keyed on reduce motion; both gears' open tween on the `emphasized` curve and instant under reduce motion.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/app_reduce_motion_test.dart`:

```dart
  testWidgets('reduce motion makes the theme swap instant', (tester) async {
    await tester.pumpWidget(app(reduceMotion: true));
    final mApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(mApp.themeAnimationDuration, Duration.zero);
  });

  testWidgets('with motion on, the theme swap keeps the default tween',
      (tester) async {
    await tester.pumpWidget(app(reduceMotion: false));
    final mApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(mApp.themeAnimationDuration, kThemeAnimationDuration);
    await tester.pump(const Duration(milliseconds: 900)); // settle reveal
  });
```

(`kThemeAnimationDuration` comes from `package:flutter/material.dart`, already imported by the test.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/app_reduce_motion_test.dart`
Expected: FAIL — `themeAnimationDuration` is the framework default (`kThemeAnimationDuration`) even when reduce motion is on.

- [ ] **Step 3: Make the theme swap instant under reduce motion**

In `lib/app.dart`, in the `MaterialApp(...)`, add after `theme: themeDataFor(_theme),`:

```dart
      themeAnimationDuration:
          _reduceMotion ? Duration.zero : kThemeAnimationDuration,
      themeAnimationCurve: Motion.emphasized,
```

Add the `Motion` import near the other `core/theme` imports if not already present:

```dart
import 'core/theme/tokens/motion.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/app_reduce_motion_test.dart`
Expected: PASS (4 tests total).

- [ ] **Step 5: Polish the lobby gear open animation**

In `lib/ui/settings/lobby_settings_button.dart`, add the import near the other `core/theme` imports:

```dart
import '../../core/theme/reduce_motion.dart';
```

In `build`, change the `menuChildren` `TweenAnimationBuilder` so its duration honors reduce motion and its curve is emphasized. Replace:

```dart
          duration: const Duration(milliseconds: 160),
          curve: Motion.standard,
```

with:

```dart
          duration: context.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Motion.emphasized,
```

- [ ] **Step 6: Polish the in-room gear open animation**

In `lib/ui/player_menu_button.dart`, add the import near the other `core/theme` imports:

```dart
import '../core/theme/reduce_motion.dart';
```

In `PlayerMenuButton.build`, change the `menuChildren` `TweenAnimationBuilder`. Replace:

```dart
          duration: const Duration(milliseconds: 160),
          curve: Motion.standard,
```

with:

```dart
          duration: context.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Motion.emphasized,
```

- [ ] **Step 7: Smoke-test the gear under reduce motion + analyze**

Run:
```
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/settings/lobby_settings_button_test.dart test/ui/player_menu_button_test.dart test/app_reduce_motion_test.dart
```
Expected: `No issues found!` and green. (The gears still open and render their panels; the existing gear tests pump+settle so the `Duration.zero` path under reduce motion is exercised harmlessly.)

- [ ] **Step 8: Commit**

```bash
git add lib/app.dart lib/ui/settings/lobby_settings_button.dart lib/ui/player_menu_button.dart test/app_reduce_motion_test.dart
git commit -m "feat: instant theme swap + emphasized gear open under reduce motion"
```

---

### Task 6: Version bump + changelog + AGENT_GUIDE note + full suite

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `CHANGELOG.md`
- Modify: `docs/AGENT_GUIDE.md`

**Interfaces:** none (release metadata + docs).

- [ ] **Step 1: Bump the version (lockstep)**

In `pubspec.yaml`, set:

```yaml
version: 0.37.0-alpha+1
```

In `lib/core/app_version.dart`, set:

```dart
const String appVersion = '0.37.0-alpha';
```

- [ ] **Step 2: Add the changelog entry**

Insert at the top of `CHANGELOG.md` (above the `0.36.1-alpha` entry), written for the end user:

```markdown
## [0.37.0-alpha] - 2026-06-26

> The lobby comes alive — and a Reduce motion switch for when you'd rather it didn't.

### Added
- A **Reduce motion** setting in the gear menu (lobby and in-room). Turn it on
  and every animation drops to an instant — no splash, no slides, no cascades.
  MeowWatch also follows your system "reduce animations" setting automatically.

### Improved
- The lobby's saved rooms and continue-watching cards now **ripple in** when the
  app opens, just after the welcome.
- Opening a room now **rises and fades in** instead of snapping, and reverses as
  you leave.
- The settings menu opens with a smoother curve.
```

- [ ] **Step 3: Update the AGENT_GUIDE motion note**

In `docs/AGENT_GUIDE.md`, find the Motion subsection's closing sentence:

```
The in-app Settings reduce-motion toggle is planned for the Lobby motion phase.
```

Replace it with:

```
The in-app **Reduce motion** setting (lobby + in-room gear, key
`kReduceMotionSettingKey`) flips `context.reduceMotion` app-wide via a
`ReduceMotionScope` injected in `MaterialApp.builder`; the OS "reduce animations"
setting forces the same independently. Lobby motion primitives draw from the same
tokens: `fadeUpRoute` (`lib/ui/motion/fade_up_route.dart`) is the rise+fade room
push, and `StaggeredReveal` (`lib/ui/motion/staggered_reveal.dart`) is the
cold-start card cascade — both go instant under reduce motion.
```

- [ ] **Step 4: Run the full suite + analyze**

Run:
```
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test
```
Expected: `No issues found!` and all tests green. (If the local suite hangs at "loading …" or a self-hosted CI run cancels at ~20 min, suspect stale `flutter_tester` zombies, not a code bug — kill stale `flutter_tester` processes, NOT `meowwatch.exe`, then re-run.)

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml lib/core/app_version.dart CHANGELOG.md docs/AGENT_GUIDE.md
git commit -m "chore: release 0.37.0-alpha — lobby motion + Reduce motion setting"
```

---

## Post-implementation (release flow — not a coding task)

After all tasks are green locally (analyze + test), follow the repo release flow
(`docs/AGENT_GUIDE.md` "Release flow"):

1. This is a **visible UX change** → before opening the PR, build the Release and
   open it for an **early local look**: verify the card cascade after the splash,
   the fade-up into a room, the theme cross-fade, and the Reduce-motion switch
   making all of it instant (try it with the OS "reduce animations" both off and
   on). Kill only the build-output `meowwatch.exe` before `flutter build windows`.
   Fold in feedback.
2. Open the PR to `main`; wait for the auto Copilot/Codex review; run
   `address-pr-review`.
3. Request the single manual test only once reviews + CI are clear.
4. CI green (`Analyze & Test`, self-hosted — start the runner if its job is
   queued) → merge.
5. `git checkout main && git pull` → tag `v0.37.0-alpha` on the merge commit →
   `git push origin v0.37.0-alpha`.
6. Watch the release run green → verify R2 (`latest.json` version = 0.37.0-alpha;
   `changelog.json` array includes it) → stop the runner → delete the branch.

## What this plan deliberately does NOT do (deferred, per spec phasing)

- **In-room + everyday controls** (banners, paw-burst reactions, idle mascot,
  auto-hiding playback bar, app-wide `PressableScale`) — Phase 3.
- **Motion-principles looping specimens + per-letter wordmark stagger** — Phase 4.
- **Gallery specimens for the fade-up route / cascade** — optional, omitted to
  keep the gallery test stable; the primitives are exercised by their own tests.
- **Per-element form cascade** and a theme-switch wash echo — the form rises with
  the launch reveal as one block and the palette already cross-fades.
- **Finer per-row ripple inside continue-watching** — the cascade treats that
  block as one entrance item; reaching inside would mean changing
  `StaggeredReflowList`, which this phase leaves untouched.
- **Reveal/transition golden tests** — deferred, as in Phase 1.
```
