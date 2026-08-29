# Launch Reveal + Motion Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MeowWatch's cold-start launch reveal — a theme-gradient wash + animated logo that dissolves as the lobby rises in — plus the minimal motion foundation (new tokens, a `RevealIn` primitive, and an OS-honored reduce-motion path) the reveal needs.

**Architecture:** The reveal is a self-contained `LaunchReveal` widget that wraps the lobby in `app.dart`'s `home:`. It renders a `Stack` of the lobby (with a fade+rise transition) under a splash overlay (wash + wordmark + mark + tip), driven by one `AnimationController` over the `Motion.reveal` token. Pushed routes are unaffected. The post-update "What's new" modal moves from `initState` to fire on reveal-complete so it no longer pops over the animation. Reduce-motion is a `context.reduceMotion` accessor (OS `disableAnimations` ∥ an optional `ReduceMotionScope`); when on, every motion primitive degrades to an instant present.

**Tech Stack:** Flutter desktop (Windows-first), Dart, `AnimationController` + `Interval`/`CurvedAnimation`, the existing `MeowLogoMark` / `MeowWordmark` (shipped in 0.35.0-alpha), `CustomPainter`-free.

## Global Constraints

- **Toolchain (NOT on PATH):** `FLUTTER=%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat`. Run `$FLUTTER analyze` (keep "No issues found!") and `$FLUTTER test` locally — never defer to CI.
- **TDD:** RED → GREEN → REFACTOR. Small conventional-commit (`feat:` / `test:` / `refactor:`) checkpoints at each verified step.
- **Versioning (lockstep, this PR is one MINOR bump):** `pubspec.yaml` `version:` → `0.36.0-alpha+1`, `lib/core/app_version.dart` `appVersion` → `'0.36.0-alpha'`, and a new top `## [0.36.0-alpha] - 2026-06-25` entry in `CHANGELOG.md`. Keep the `-alpha` suffix.
- **Immutability / file size:** new objects over mutation; keep files focused (200–400 lines typical).
- **Never block input at launch:** the reveal is skippable on any click/key, overlaps real warmup, and adds no perceptible wait. Vector mark only — no image decode at frame one.
- **Cold-start only:** the reveal plays on process launch over the lobby, never on a screen change or a pushed route.
- **No `Date.now()`/randomness in tests** — gallery/demo data uses fixed values (repo convention).
- **Scope note (carried from the spec):** the in-app *Settings → Reduce motion* toggle and its gear plumbing are **deferred to Phase 2 (Lobby)**. This PR honors the OS reduce-animations setting and ships a gallery preview toggle; that is the "reduce-motion switch" Phase 1 needs.

**Source of truth:** `docs/superpowers/specs/2026-06-25-motion-and-launch-reveal-design.md` (Sections A, B, D; Phase 1).

---

### Task 1: Motion tokens (`reveal`, `emphasized`, `emphasizedAccelerate`, `springy`)

**Files:**
- Modify: `lib/core/theme/tokens/motion.dart`
- Test: `test/core/theme/tokens/motion_test.dart`

**Interfaces:**
- Produces: `Motion.reveal` (`Duration`), `Motion.emphasized` / `Motion.emphasizedAccelerate` / `Motion.springy` (`Curve`). Consumed by Tasks 3, 5, 7.

- [ ] **Step 1: Add the failing token tests**

Append inside `main()` in `test/core/theme/tokens/motion_test.dart`:

```dart
  test('reveal is the launch-only duration, the longest token', () {
    expect(Motion.reveal, const Duration(milliseconds: 800));
    expect(Motion.slow < Motion.reveal, isTrue);
  });

  test('the hero/character easings are the agreed cubics', () {
    expect(Motion.emphasized, Curves.easeInOutCubicEmphasized);
    expect(Motion.emphasizedAccelerate, const Cubic(0.3, 0.0, 0.8, 0.15));
    expect(Motion.springy, const Cubic(0.34, 1.26, 0.64, 1.0));
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/theme/tokens/motion_test.dart`
Expected: FAIL — `Motion.reveal` / `Motion.emphasized` etc. are undefined.

- [ ] **Step 3: Add the tokens**

In `lib/core/theme/tokens/motion.dart`, add after `static const Duration stagger = ...;`:

```dart
  /// The cold-start launch reveal's total timeline. The longest token, used
  /// nowhere else — the splash wash → wordmark → dissolve all fit inside it.
  static const Duration reveal = Duration(milliseconds: 800);
```

and after `static const Curve symmetric = ...;`:

```dart
  /// Material 3 "emphasized" — the hero enter for big, expressive moves
  /// (the launch reveal, panels). Slow-in/slow-out with a confident middle.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// The hero *exit* counterpart: starts quick, eases out — used when a hero
  /// element leaves (the reveal's wash dissolving away).
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// The single "character" curve: a mild overshoot that settles. Used sparingly
  /// for the one playful beat (the mark settling in). Deliberately gentle, not
  /// elastic.
  static const Curve springy = Cubic(0.34, 1.26, 0.64, 1.0);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/theme/tokens/motion_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens/motion.dart test/core/theme/tokens/motion_test.dart
git commit -m "feat: add reveal duration + emphasized/springy motion easings"
```

---

### Task 2: Reduce-motion mechanism (`ReduceMotionScope` + `context.reduceMotion`)

**Files:**
- Create: `lib/core/theme/reduce_motion.dart`
- Test: `test/core/theme/reduce_motion_test.dart`

**Interfaces:**
- Produces:
  - `class ReduceMotionScope extends InheritedWidget { const ReduceMotionScope({required bool reduceMotion, required Widget child}); }`
  - `extension ReduceMotionContext on BuildContext { bool get reduceMotion; }` — true when the nearest `ReduceMotionScope` is on **or** `MediaQuery.disableAnimationsOf(this)` is true.
- Consumed by Tasks 3, 5, 7.

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/reduce_motion_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';

void main() {
  testWidgets('reduceMotion is false by default', (tester) async {
    late bool value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          value = context.reduceMotion;
          return const SizedBox();
        }),
      ),
    );
    expect(value, isFalse);
  });

  testWidgets('a ReduceMotionScope turns it on for descendants',
      (tester) async {
    late bool value;
    await tester.pumpWidget(
      MaterialApp(
        home: ReduceMotionScope(
          reduceMotion: true,
          child: Builder(builder: (context) {
            value = context.reduceMotion;
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(value, isTrue);
  });

  testWidgets('the OS disableAnimations flag turns it on', (tester) async {
    late bool value;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(builder: (context) {
            value = context.reduceMotion;
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(value, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/theme/reduce_motion_test.dart`
Expected: FAIL — `reduce_motion.dart` does not exist.

- [ ] **Step 3: Create the scope + accessor**

Create `lib/core/theme/reduce_motion.dart`:

```dart
import 'package:flutter/material.dart';

/// Carries the app-level "reduce motion" preference down the tree. When on,
/// motion primitives degrade to an instant present (no rise, no overshoot).
/// In Phase 1 it is only ever set by the design gallery's preview toggle; the
/// in-app Settings toggle that flips it app-wide lands in the Lobby phase.
class ReduceMotionScope extends InheritedWidget {
  const ReduceMotionScope({
    required this.reduceMotion,
    required super.child,
    super.key,
  });

  final bool reduceMotion;

  static bool of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ReduceMotionScope>();
    return scope?.reduceMotion ?? false;
  }

  @override
  bool updateShouldNotify(ReduceMotionScope old) =>
      old.reduceMotion != reduceMotion;
}

/// `context.reduceMotion` — true when this app's scope says so OR the OS
/// "reduce animations" accessibility setting is on. Every motion primitive
/// reads this so no screen has to special-case it.
extension ReduceMotionContext on BuildContext {
  bool get reduceMotion =>
      ReduceMotionScope.of(this) || MediaQuery.disableAnimationsOf(this);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/theme/reduce_motion_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/reduce_motion.dart test/core/theme/reduce_motion_test.dart
git commit -m "feat: add reduce-motion scope + context.reduceMotion accessor"
```

---

### Task 3: `RevealIn` primitive (fade + rise, reduce-motion aware)

**Files:**
- Create: `lib/ui/motion/reveal_in.dart`
- Test: `test/ui/motion/reveal_in_test.dart`

**Interfaces:**
- Consumes: `Motion.base`, `Motion.emphasized`, `Motion.springy` (Task 1); `context.reduceMotion` (Task 2).
- Produces: `class RevealIn extends StatefulWidget { const RevealIn({required Widget child, Duration delay, double offset, Duration duration, bool overshoot, Key? key}); }` — fades + rises `child` in once on mount. `offset` defaults `16` (logical px it rises from). `overshoot` defaults `false` (uses `Motion.springy` when true). Reduce-motion → child shown instantly, fully present. Consumed by Tasks 5, 7.

- [ ] **Step 1: Write the failing test**

Create `test/ui/motion/reveal_in_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';
import 'package:meowwatch/ui/motion/reveal_in.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('starts faded/below and settles to fully present',
      (tester) async {
    await tester.pumpWidget(_host(const RevealIn(child: Text('hi'))));

    // First frame: not yet fully opaque.
    final start = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(start.opacity, lessThan(1.0));

    // After the animation: fully opaque, no residual offset.
    await tester.pump(const Duration(milliseconds: 400));
    final end = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(end.opacity, 1.0);
  });

  testWidgets('reduce motion shows the child instantly at full opacity',
      (tester) async {
    await tester.pumpWidget(
      _host(const RevealIn(child: Text('hi')), reduceMotion: true),
    );
    await tester.pump(); // one frame, no animation scheduled
    final op = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(op.opacity, 1.0);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/motion/reveal_in_test.dart`
Expected: FAIL — `reveal_in.dart` does not exist.

- [ ] **Step 3: Create the primitive**

Create `lib/ui/motion/reveal_in.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/motion.dart';

/// Fades + rises [child] into view once, on first mount. The everyday "this
/// just appeared" enter used by the launch reveal's lobby content and the
/// gallery demos. Honors reduce motion: when on, [child] is shown instantly,
/// fully present, with no rise and no overshoot.
class RevealIn extends StatefulWidget {
  const RevealIn({
    required this.child,
    this.delay = Duration.zero,
    this.offset = 16,
    this.duration = Motion.base,
    this.overshoot = false,
    super.key,
  });

  final Widget child;

  /// How long to wait after mount before starting (for cascades).
  final Duration delay;

  /// Logical pixels the child rises from (translate-up distance).
  final double offset;

  final Duration duration;

  /// When true, the rise settles with the gentle [Motion.springy] overshoot;
  /// otherwise [Motion.emphasized].
  final bool overshoot;

  @override
  State<RevealIn> createState() => _RevealInState();
}

class _RevealInState extends State<RevealIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _kicked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kicked) return;
    _kicked = true;
    if (context.reduceMotion) {
      _c.value = 1; // instant present
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _c,
      curve: widget.overshoot ? Motion.springy : Motion.emphasized,
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value;
        return Opacity(
          // Opacity must stay in [0,1] even when springy overshoots past 1.
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/motion/reveal_in_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/motion/reveal_in.dart test/ui/motion/reveal_in_test.dart
git commit -m "feat: add RevealIn fade+rise primitive (reduce-motion aware)"
```

---

### Task 4: `LaunchTips` (extensible tip list)

**Files:**
- Create: `lib/ui/launch/launch_tips.dart`
- Test: `test/ui/launch/launch_tips_test.dart`

**Interfaces:**
- Produces:
  - `const List<String> kLaunchTips` — first element is the skip hint.
  - `String launchTip(int index)` — `kLaunchTips[index % kLaunchTips.length]`, safe for any int.
- Consumed by Tasks 5, 6.

- [ ] **Step 1: Write the failing test**

Create `test/ui/launch/launch_tips_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/launch/launch_tips.dart';

void main() {
  test('the first tip is the skip hint', () {
    expect(kLaunchTips, isNotEmpty);
    expect(kLaunchTips.first.toLowerCase(), contains('skip'));
  });

  test('launchTip wraps the index around the list', () {
    expect(launchTip(0), kLaunchTips.first);
    expect(launchTip(kLaunchTips.length), kLaunchTips.first);
    expect(launchTip(-1), kLaunchTips.last); // Dart % can be negative-safe here
  });
}
```

Note: Dart's `%` on a negative dividend with a positive divisor returns a
non-negative result (`-1 % 3 == 2`), so `launchTip(-1)` is the last element.

- [ ] **Step 2: Run the test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/launch/launch_tips_test.dart`
Expected: FAIL — `launch_tips.dart` does not exist.

- [ ] **Step 3: Create the tips**

Create `lib/ui/launch/launch_tips.dart`:

```dart
/// One short, low-emphasis line shown late under the launch wordmark. The first
/// is always the skip hint; later tips are an extensible list — add one line
/// each (e.g. "Drag a video anywhere to load it.", "Press Tab to open chat.").
/// One tip shows per launch.
const List<String> kLaunchTips = <String>[
  'Click or press any key to skip.',
  'Drag a video anywhere to load it.',
  'Press Tab to open chat.',
  'Share your room code — your friend joins from one paste.',
];

/// The tip for [index], wrapping around the list so any seed is valid.
String launchTip(int index) => kLaunchTips[index % kLaunchTips.length];
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/launch/launch_tips_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/launch/launch_tips.dart test/ui/launch/launch_tips_test.dart
git commit -m "feat: add extensible LaunchTips list + launchTip accessor"
```

---

### Task 5: `LaunchReveal` widget + controller (the headline)

**Files:**
- Create: `lib/ui/launch/launch_reveal.dart`
- Test: `test/ui/launch/launch_reveal_test.dart`

**Interfaces:**
- Consumes: `Motion.reveal` / `Motion.emphasized` / `Motion.emphasizedAccelerate` / `Motion.springy` / `Motion.fast` (Task 1); `context.reduceMotion` (Task 2); `MeowWordmark` (`lib/ui/brand/meow_wordmark.dart`), `MeowLogoMark` (`lib/ui/brand/meow_logo_mark.dart`); `kLaunchTips` (Task 4); `context.meow` (`lib/core/theme/meow_context.dart`).
- Produces: `class LaunchReveal extends StatefulWidget { const LaunchReveal({required Widget child, required VoidCallback onComplete, bool enabled = true, String? tip, Key? key}); }` — overlays a one-shot splash over [child]; calls [onComplete] exactly once when the reveal settles (or, when `enabled` is false / reduce-motion, after the first frame). Splash root has `key: const Key('launch-reveal-splash')`. Consumed by Task 6.

- [ ] **Step 1: Write the failing test**

Create `test/ui/launch/launch_reveal_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/launch/launch_reveal.dart';

const _splash = Key('launch-reveal-splash');

Widget _host(
  Widget reveal, {
  bool reduceMotion = false,
}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: themeDataFor(MeowThemeId.aurora),
        home: Scaffold(body: reveal),
      ),
    );

void main() {
  testWidgets('plays then settles to the child and removes the splash',
      (tester) async {
    var completed = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        onComplete: () => completed++,
        child: const Text('LOBBY'),
      ),
    ));

    // Mid-reveal: the splash is up.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(_splash), findsOneWidget);
    expect(completed, 0);

    // After the full timeline: splash gone, child present, completed once.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(_splash), findsNothing);
    expect(find.text('LOBBY'), findsOneWidget);
    expect(completed, 1);
  });

  testWidgets('any tap skips straight to the settled lobby', (tester) async {
    var completed = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        onComplete: () => completed++,
        child: const Text('LOBBY'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_splash), findsOneWidget);

    await tester.tap(find.byKey(_splash));
    await tester.pump(); // start the fast skip
    await tester.pump(const Duration(milliseconds: 200)); // finish it
    expect(find.byKey(_splash), findsNothing);
    expect(completed, 1);
  });

  testWidgets('reduce motion shows the lobby immediately, no splash',
      (tester) async {
    var completed = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        onComplete: () => completed++,
        child: const Text('LOBBY'),
      ),
      reduceMotion: true,
    ));
    await tester.pump(); // run the post-frame complete
    expect(find.byKey(_splash), findsNothing);
    expect(find.text('LOBBY'), findsOneWidget);
    expect(completed, 1);
  });

  testWidgets('disabled passes the child straight through', (tester) async {
    var completed = 0;
    await tester.pumpWidget(_host(
      LaunchReveal(
        enabled: false,
        onComplete: () => completed++,
        child: const Text('LOBBY'),
      ),
    ));
    await tester.pump();
    expect(find.byKey(_splash), findsNothing);
    expect(find.text('LOBBY'), findsOneWidget);
    expect(completed, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/launch/launch_reveal_test.dart`
Expected: FAIL — `launch_reveal.dart` does not exist.

- [ ] **Step 3: Create the reveal**

Create `lib/ui/launch/launch_reveal.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/meow_context.dart';
import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/spacing.dart';
import '../brand/meow_logo_mark.dart';
import '../brand/meow_wordmark.dart';
import 'launch_tips.dart';

/// The cold-start launch reveal. Overlays a one-shot splash — the active
/// theme's gradient washing in, the logo mark settling, the "MeowWatch"
/// wordmark easing in, and a late skip tip — over [child] (the lobby), then
/// dissolves as the lobby rises in behind it. Calls [onComplete] exactly once
/// when it settles, so the caller can sequence what comes next (e.g. the
/// post-update "What's new" modal) AFTER the animation rather than over it.
///
/// Skippable on any click or key. When [enabled] is false or the OS / app
/// "reduce motion" setting is on, the child is shown immediately and
/// [onComplete] fires after the first frame — no splash, no wait.
class LaunchReveal extends StatefulWidget {
  const LaunchReveal({
    required this.child,
    required this.onComplete,
    this.enabled = true,
    this.tip,
    super.key,
  });

  final Widget child;
  final VoidCallback onComplete;
  final bool enabled;

  /// The line shown late under the wordmark. Defaults to the skip hint.
  final String? tip;

  @override
  State<LaunchReveal> createState() => _LaunchRevealState();
}

class _LaunchRevealState extends State<LaunchReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.reveal,
  );
  final FocusNode _skipFocus = FocusNode(debugLabel: 'launch-reveal-skip');
  bool _started = false;
  bool _done = false;

  // Timeline intervals over [Motion.reveal] (800ms).
  static const _washIn = Interval(0.0, 0.25, curve: Motion.emphasized);
  static const _markIn = Interval(0.15, 0.55, curve: Motion.springy);
  static const _wordIn = Interval(0.15, 0.55, curve: Motion.emphasized);
  static const _tipIn = Interval(0.45, 0.65, curve: Motion.emphasized);
  static const _dissolve =
      Interval(0.70, 1.0, curve: Motion.emphasizedAccelerate);
  static const _lobbyRise = Interval(0.70, 1.0, curve: Motion.emphasized);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || context.reduceMotion) {
      _finishAfterFrame();
      return;
    }
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _c.forward();
  }

  void _finishAfterFrame() {
    // Skip the splash entirely, but still complete after a frame so callers
    // sequence the same way they would after a real reveal.
    _done = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onComplete();
    });
  }

  void _finish() {
    if (_done) return;
    setState(() => _done = true);
    widget.onComplete();
  }

  void _skip() {
    if (_done || _c.status == AnimationStatus.completed) return;
    // Jump quickly to the settled lobby rather than a hard cut.
    _c.animateTo(1.0,
        duration: Motion.fast, curve: Motion.emphasizedAccelerate);
  }

  @override
  void dispose() {
    _c.dispose();
    _skipFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final m = context.meow;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The lobby underneath, rising + fading in during the dissolve.
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = _lobbyRise.transform(_c.value);
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 16),
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
        // The splash overlay: tap/key anywhere skips.
        Positioned.fill(
          child: Focus(
            focusNode: _skipFocus,
            autofocus: true,
            onKeyEvent: (_, __) {
              _skip();
              return KeyEventResult.handled;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _skip,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final wash = _washIn.transform(_c.value);
                  final dissolve = 1 - _dissolve.transform(_c.value);
                  return Opacity(
                    opacity: dissolve, // whole splash fades out at the end
                    child: _splash(m, wash),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _splash(MeowColors m, double wash) {
    final gradient = m.backgroundGradient;
    return DecoratedBox(
      key: const Key('launch-reveal-splash'),
      decoration: BoxDecoration(
        color: gradient == null
            ? Color.lerp(m.background.withValues(alpha: 0), m.background, wash)
            : null,
        gradient: gradient == null
            ? null
            : LinearGradient(
                begin: (gradient as LinearGradient).begin,
                end: gradient.end,
                colors: [
                  for (final col in gradient.colors)
                    Color.lerp(col.withValues(alpha: 0), col, wash)!,
                ],
              ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mark — settles in with the springy character beat.
            _phase(_markIn, child: const MeowLogoMark(size: 88)),
            const SizedBox(height: Spacing.lg),
            // Wordmark — eases in just behind the mark.
            _phase(_wordIn, child: const MeowWordmark(fontSize: 34)),
            const SizedBox(height: Spacing.xxl),
            // Tip — fades in late so it never competes with the hero beat.
            _phase(
              _tipIn,
              rise: 6,
              child: Text(
                widget.tip ?? kLaunchTips.first,
                style: TextStyle(
                  color: m.textDim,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fade + small rise of one splash element, driven by its [interval].
  Widget _phase(Interval interval, {required Widget child, double rise = 12}) {
    final t = interval.transform(_c.value);
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - t) * rise),
        child: child,
      ),
    );
  }
}
```

Note for the implementer: `_splash` derives the wash gradient from the live
`MeowColors.backgroundGradient` (Aurora) or fades the flat `background` (Cozy /
Noir). It does not hardcode hexes — the brand follows whatever theme is active,
per the spec.

- [ ] **Step 4: Run the test to verify it passes**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/launch/launch_reveal_test.dart`
Expected: PASS (4 tests). If the "plays then settles" first-frame assertion is
flaky on the wash opacity, assert on `find.byKey(_splash)` presence only (it is
the stable signal); the opacity is incidental.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/launch/launch_reveal.dart test/ui/launch/launch_reveal_test.dart
git commit -m "feat: add LaunchReveal splash (wash + wordmark + dissolve, skippable)"
```

---

### Task 6: Wire `LaunchReveal` into the app + defer the What's-new modal

**Files:**
- Modify: `lib/app.dart`
- Test: `test/app_launch_reveal_test.dart` (create)
- Modify: `test/app_whats_new_test.dart:22-33` (add `showLaunchReveal: false` to the `app()` helper)
- Modify: `test/app_theme_test.dart` (add `showLaunchReveal: false` wherever it constructs `MeowWatchApp`)

**Interfaces:**
- Consumes: `LaunchReveal` (Task 5), `kLaunchTips` (Task 4).
- Produces: `MeowWatchApp({..., bool showLaunchReveal = true})`; the What's-new modal now fires from the reveal's `onComplete`, not `initState`.

- [ ] **Step 1: Write the failing test**

Create `test/app_launch_reveal_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/app.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:meowwatch/ui/launch/launch_reveal.dart';
import 'package:meowwatch/ui/whats_new_dialog.dart';

import 'support/fakes.dart';

void main() {
  Widget app({required bool showReveal, bool whatsNew = false}) => MeowWatchApp(
        profiles: FakeProfileStore(),
        history: FakeHistoryStore(),
        settings: FakeSettingsStore(),
        initialTheme: MeowThemeId.cozy,
        showLaunchReveal: showReveal,
        showWhatsNew: whatsNew,
        whatsNewEntries: const [
          ChangelogEntry(
            version: '0.36.0-alpha',
            date: '2026-06-25',
            notes: '### Added\n- the launch reveal',
          ),
        ],
      );

  testWidgets('cold start shows the launch reveal over the lobby',
      (tester) async {
    await tester.pumpWidget(app(showReveal: true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('launch-reveal-splash')), findsOneWidget);
    // Let it settle so the test tears down cleanly.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('launch-reveal-splash')), findsNothing);
  });

  testWidgets('the What\'s-new modal waits until the reveal finishes',
      (tester) async {
    await tester.pumpWidget(app(showReveal: true, whatsNew: true));
    // Mid-reveal the modal is NOT up yet (it used to pop over the splash).
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(WhatsNewDialog), findsNothing);
    // After the reveal completes, the modal appears.
    await tester.pump(const Duration(milliseconds: 900)); // reveal completes
    await tester.pump(); // onComplete → showDialog
    await tester.pump(const Duration(milliseconds: 350)); // route transition
    expect(find.byType(WhatsNewDialog), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/app_launch_reveal_test.dart`
Expected: FAIL — `showLaunchReveal` is not a parameter of `MeowWatchApp`, and the splash never mounts.

- [ ] **Step 3: Wire the reveal into `app.dart`**

In `lib/app.dart`:

(a) Add the import near the other `ui/` imports:

```dart
import 'ui/launch/launch_reveal.dart';
```

(b) Add the constructor field. In the `const MeowWatchApp({...})` parameter list, add `this.showLaunchReveal = true,` (before `super.key,`), and add the field declaration with the other finals:

```dart
  /// Whether to play the cold-start launch reveal over the lobby. True in
  /// production; false in tests that drive the lobby/What's-new directly.
  final bool showLaunchReveal;
```

(c) Replace the `initState` What's-new trigger with a deferred path. Change the
`_MeowWatchAppState` so the modal fires when the reveal completes. Replace the
existing `initState` body with:

```dart
  bool _whatsNewShown = false;

  void _onRevealComplete() {
    if (_whatsNewShown) return;
    _whatsNewShown = true;
    final entries = widget.whatsNewEntries;
    if (!widget.showWhatsNew || entries.isEmpty) return;
    final context = _navKey.currentContext;
    if (context != null) WhatsNewDialog.show(context, entries);
  }
```

(Delete the old `initState` override entirely — the post-frame callback moves
into `_onRevealComplete`, which the reveal calls. The `late final _navKey`
declaration stays as-is.)

(d) Wrap the `home:` child in `LaunchReveal`. Replace `home: Builder(builder: (context) => ConnectScreen(...))` so the `ConnectScreen` is the reveal's child:

```dart
      home: Builder(
        builder: (context) => LaunchReveal(
          enabled: widget.showLaunchReveal,
          onComplete: _onRevealComplete,
          child: ConnectScreen(
            profiles: widget.profiles,
            history: widget.history,
            settings: widget.settings,
            currentTheme: _theme,
            onThemeChanged: _setTheme,
            onConnect: (RoomConfig config) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HomeScreen(
                  config: config,
                  history: widget.history,
                  settings: widget.settings,
                  initialWidthPx: widget.initialCardWidthPx,
                  initialHeightPx: widget.initialCardHeightPx,
                  currentTheme: _theme,
                  onThemeChanged: _setTheme,
                ),
              ),
            ),
          ),
        ),
      ),
```

- [ ] **Step 4: Update the two app-level tests to opt out of the reveal**

In `test/app_whats_new_test.dart`, add `showLaunchReveal: false,` to the
`MeowWatchApp(...)` in the `app({required bool show, ...})` helper (around
line 26–33). The What's-new timing assertions there are unchanged because the
disabled reveal fires `onComplete` after the first frame.

In `test/app_theme_test.dart`, add `showLaunchReveal: false,` to every
`MeowWatchApp(...)` construction (so theme-switch taps land on the lobby, not
the splash).

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```
%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/app_launch_reveal_test.dart test/app_whats_new_test.dart test/app_theme_test.dart
```
Expected: PASS (all). If `app_theme_test` taps a theme pill, confirm it no
longer hits the splash (it shouldn't, with `showLaunchReveal: false`).

- [ ] **Step 6: Commit**

```bash
git add lib/app.dart test/app_launch_reveal_test.dart test/app_whats_new_test.dart test/app_theme_test.dart
git commit -m "feat: play the launch reveal on cold start; defer What's-new modal behind it"
```

---

### Task 7: Gallery — new-token specimens, `RevealIn` demo, reveal replay + reduce-motion preview

**Files:**
- Modify: `lib/ui/gallery/gallery_sections.dart`
- Test: `test/ui/gallery/design_gallery_test.dart`

**Interfaces:**
- Consumes: `Motion.reveal/emphasized/emphasizedAccelerate/springy` (Task 1), `ReduceMotionScope` (Task 2), `RevealIn` (Task 3), `LaunchReveal` (Task 5), `kLaunchTips` (Task 4).
- Produces: a `MotionRevealSpecimen` widget + a `'Motion · reveal'` `GallerySection` inserted right after `'Motion · list reflow'`. Extends the existing `MotionSpecimen` token chips with the four new tokens.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/ui/gallery/design_gallery_test.dart`:

```dart
  testWidgets('gallery includes the launch-reveal motion section',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pump(const Duration(milliseconds: 300));

    // The section is lazy; step-scroll until its title is built.
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0;
        i < 30 && find.text('MOTION · REVEAL').evaluate().isEmpty;
        i++) {
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('MOTION · REVEAL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/gallery/design_gallery_test.dart`
Expected: FAIL — there is no `'Motion · reveal'` section.

- [ ] **Step 3: Add the specimen + section + token chips**

In `lib/ui/gallery/gallery_sections.dart`:

(a) Add imports near the other `../` imports:

```dart
import '../../core/theme/reduce_motion.dart';
import '../launch/launch_reveal.dart';
import '../launch/launch_tips.dart';
import '../motion/reveal_in.dart';
```

(b) Extend the token chips in `MotionSpecimen.build` — add to the final
`Wrap(...children: [...])` chip list (after `chip('symmetric · easeInOut')`):

```dart
          chip('reveal · ${Motion.reveal.inMilliseconds}ms'),
          chip('emphasized · easeInOutCubicEmphasized'),
          chip('emphasizedAccelerate · (.3, 0, .8, .15)'),
          chip('springy · (.34, 1.26, .64, 1)'),
```

(c) Add the new specimen class (place it just after the `MotionReflowSpecimen`
class, before `ShadowSpecimen`):

```dart
/// The launch-reveal motion, live: a [RevealIn] demo you can replay, a
/// reduce-motion preview toggle that forces the degraded (instant) form, and a
/// "Play full launch reveal" button that runs the real [LaunchReveal] over a
/// placeholder lobby. The replay tile lets the splash live in the design system.
class MotionRevealSpecimen extends StatefulWidget {
  const MotionRevealSpecimen({super.key});

  @override
  State<MotionRevealSpecimen> createState() => _MotionRevealSpecimenState();
}

class _MotionRevealSpecimenState extends State<MotionRevealSpecimen> {
  bool _reduceMotion = false;
  int _replayKey = 0; // bump to remount the RevealIn demo

  void _playFullReveal() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullRevealReplay(reduceMotion: _reduceMotion),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    return ReduceMotionScope(
      reduceMotion: _reduceMotion,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Reduce motion',
                  style: t.body.copyWith(color: c.textPrimary)),
              const SizedBox(width: Spacing.md),
              Switch(
                value: _reduceMotion,
                activeColor: c.accent,
                onChanged: (v) => setState(() {
                  _reduceMotion = v;
                  _replayKey++;
                }),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          // RevealIn demo — remounts on replay so the fade+rise replays.
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RevealIn(
                  key: ValueKey('reveal-in-$_replayKey-$_reduceMotion'),
                  overshoot: true,
                  child: Text('RevealIn',
                      style: t.title.copyWith(color: c.accent)),
                ),
                TextButton(
                  onPressed: () => setState(() => _replayKey++),
                  style: TextButton.styleFrom(foregroundColor: c.accent),
                  child: const Text('Replay'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton.icon(
            onPressed: _playFullReveal,
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.background,
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play full launch reveal'),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Tip shown: “${kLaunchTips.first}”',
            style: t.caption.copyWith(color: c.textDim),
          ),
        ],
      ),
    );
  }
}

/// Full-screen replay of the real [LaunchReveal] over a placeholder lobby, so
/// the splash can be reviewed in the gallery exactly as it ships.
class _FullRevealReplay extends StatelessWidget {
  const _FullRevealReplay({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    return ReduceMotionScope(
      reduceMotion: reduceMotion,
      child: Scaffold(
        backgroundColor: c.background,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: c.backgroundGradient,
            color: c.backgroundGradient == null ? c.background : null,
          ),
          child: LaunchReveal(
            onComplete: () {},
            child: Center(
              child: Text('Lobby', style: context.meowText.display),
            ),
          ),
        ),
      ),
    );
  }
}
```

(d) Insert the section into `gallerySections()` — add immediately after the
`'Motion · list reflow'` `GallerySection(...)`:

```dart
      GallerySection(
        title: 'Motion · reveal',
        description:
            'The cold-start launch reveal + its RevealIn primitive. Toggle '
            'reduce motion to preview the instant, degraded form; replay the '
            'full splash to review it as it ships.',
        child: MotionRevealSpecimen(),
      ),
```

Note: `gallerySections()` currently returns `const [...]`. `MotionRevealSpecimen`
is not `const` (it is `StatefulWidget` with mutable state) — drop the `const`
from the list literal (change `=> const [` to `=> [` and the entries stay as
they are; the other `GallerySection(...)` entries remain `const`-constructed
implicitly where possible). Run `analyze` and add `const` back to individual
entries the linter flags via `prefer_const_constructors` (all except the new
one).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/ui/gallery/design_gallery_test.dart`
Expected: PASS (existing tests + the new one).

- [ ] **Step 5: Verify analyze is clean (the `const` change above is the risk)**

Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat analyze`
Expected: `No issues found!` — fix any `prefer_const_constructors` by adding
`const` to the unaffected `GallerySection(...)` entries.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/gallery/gallery_sections.dart test/ui/gallery/design_gallery_test.dart
git commit -m "feat: gallery — launch-reveal motion section + new token chips + reduce-motion preview"
```

---

### Task 8: Version bump + changelog + AGENT_GUIDE motion note

**Files:**
- Modify: `pubspec.yaml` (`version:`)
- Modify: `lib/core/app_version.dart` (`appVersion`)
- Modify: `CHANGELOG.md` (new top entry)
- Modify: `docs/AGENT_GUIDE.md` (short Motion note)

**Interfaces:** none (release metadata + docs).

- [ ] **Step 1: Bump the version (lockstep)**

In `pubspec.yaml`, set the version line:

```yaml
version: 0.36.0-alpha+1
```

In `lib/core/app_version.dart`, set:

```dart
const String appVersion = '0.36.0-alpha';
```

- [ ] **Step 2: Add the changelog entry**

Insert at the top of `CHANGELOG.md` (above the `0.35.0-alpha` entry), written
for the end user (hero line + chip section):

```markdown
## [0.36.0-alpha] - 2026-06-25

> MeowWatch greets you with a real launch now.

### Added
- A cold-start **launch reveal**: the theme washes in, the logo settles, and
  the lobby rises in behind it. Click or press any key to skip it.
- A **Reduce motion** path: when your system has "reduce animations" on,
  MeowWatch shows the lobby instantly with no splash.
```

- [ ] **Step 3: Add the AGENT_GUIDE motion note**

In `docs/AGENT_GUIDE.md`, add a short subsection (under the Workflow or a new
"Motion" heading near the design-system notes):

```markdown
### Motion

Timing + easing live in `lib/core/theme/tokens/motion.dart` (`Motion.*`). New
work draws from these tokens, never ad-hoc durations. Honor reduce motion via
`context.reduceMotion` (`lib/core/theme/reduce_motion.dart`) — it's true when
the OS "reduce animations" setting is on; every motion primitive (`RevealIn`,
`LaunchReveal`) degrades to an instant present when it is. The cold-start
`LaunchReveal` (`lib/ui/launch/`) overlays the lobby and must never block input
(skippable on any click/key). The in-app Settings reduce-motion toggle is
planned for the Lobby motion phase.
```

- [ ] **Step 4: Run the full suite + analyze**

Run:
```
%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat analyze
%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test
```
Expected: `No issues found!` and all tests green. (The pre-existing
`window_close_handler_test` "hard exit" case is a known flake — re-run it
isolated if it fails: `... test test/ui/window_close_handler_test.dart`.)

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml lib/core/app_version.dart CHANGELOG.md docs/AGENT_GUIDE.md
git commit -m "chore: release 0.36.0-alpha — launch reveal + motion foundation"
```

---

## Post-implementation (release flow — not a coding task)

After all tasks are green locally (analyze + test), follow the repo release flow
(`docs/AGENT_GUIDE.md` "Release flow"):

1. This is a **visible UX change** → before opening the PR, build the Release and
   open it for an **early local look** (the launch reveal is the whole point —
   the user will want to see it animate, in each theme). Fold in feedback. Kill
   only the build-output `meowwatch.exe` before `flutter build windows` (never
   blanket-kill — the user co-watches on a separate copy).
2. Open the PR to `main`; wait for the auto Copilot review; run `address-pr-review`.
3. Request the single manual test only once reviews + CI are clear.
4. CI green (`Analyze & Test`, self-hosted — start the runner if its job is
   queued) → merge.
5. `git checkout main && git pull` → tag `v0.36.0-alpha` on the merge commit →
   `git push origin v0.36.0-alpha`.
6. Watch the release run green → verify R2 (`latest.json` version = 0.36.0-alpha;
   `changelog.json` array includes it) → stop the runner → delete the branch.

## What this plan deliberately does NOT do (deferred, per spec phasing)

- **Per-element lobby cascade / theme cross-fade / lobby→room transition** — Phase 2 (Lobby).
- **In-app Settings → Reduce motion toggle + gear plumbing** — Phase 2 (Lobby), where it governs enough motion to matter.
- **In-room banners, paw-burst, mascot breathing, playback-bar/pressables** — Phase 3.
- **Full Disney "Motion principles" looping specimens + per-letter wordmark stagger** — Phase 4 / future refinement.
- **Golden tests of reveal frames** — the widget tests assert end-state + a key mid-frame + skip + reduce-motion, which is sufficient for this phase; goldens can be added when the visual is locked.
```
