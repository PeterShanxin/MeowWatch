# Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract every hand-typed visual value (text, spacing, radius, motion, icon/glyph, opacity, shadow) into named token scales, add an in-app gallery to review them, and migrate the ~17 UI files onto the tokens — so the app stays visually consistent as it grows.

**Architecture:** Plain `static const` token classes under `lib/core/theme/tokens/` (global, identical across all 3 themes), plus one `context.meowText` helper that composes a global type size/weight with the active theme's color and font family. Colors stay in the existing `MeowColors` ThemeExtension, untouched. A hidden-in-release gallery screen (opened by **long-pressing** the version badge — see Task 13's discovered conflict) renders every scale and the live components across all 3 themes.

**Tech Stack:** Flutter (desktop, Windows-first), `media_kit`, `drift`. Flutter binary is Puro-installed and NOT on PATH — use `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`.

**Spec:** [docs/superpowers/specs/2026-06-03-design-system-design.md](../specs/2026-06-03-design-system-design.md)

---

## Conventions for every task

- `FLUTTER` = `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`.
- After any code change: `$FLUTTER analyze` must report **No issues found!** before commit.
- Commit messages are conventional (`feat:` / `test:` / `refactor:`). Attribution is disabled globally — do not add it.
- Tokens are **plain constants**: reference them directly (`Spacing.md`, `Radii.lg`), no `BuildContext` needed — except `context.meowText`, which needs context (it reads the theme).
- New code uses `.withValues(alpha:)` (not the deprecated `.withOpacity()`).

## File structure (created/modified)

```
lib/core/theme/
  meow_theme.dart        MODIFY only if needed (currently untouched — colors stay here)
  meow_text.dart         CREATE — MeowTextStyles + context.meowText
  tokens/
    type_scale.dart      CREATE — sizes + weights (no color)
    spacing.dart         CREATE
    radii.dart           CREATE
    motion.dart          CREATE
    icon_sizes.dart      CREATE — IconSizes + Glyphs
    opacities.dart       CREATE
    shadows.dart         CREATE — scrim-derived BoxShadows
lib/ui/gallery/
    gallery_tap_counter.dart   CREATE — pure tap-burst logic (Task 9, OPTIONAL — unused by the long-press gesture)
    design_gallery.dart        CREATE — the gallery screen + theme switcher
    gallery_sections.dart      CREATE — specimen widgets for each scale + component zoo
lib/ui/version_badge.dart      MODIFY — long-press → open gallery (single-tap → update dialog unchanged)
lib/main.dart                  MODIFY — MEOWWATCH_GALLERY=1 backup door
lib/ui/**                      MODIFY — migrate literals → tokens (Phase C)
test/core/theme/tokens/*_test.dart   CREATE — one per token family
test/core/theme/meow_text_test.dart  CREATE
test/ui/gallery/gallery_tap_counter_test.dart  CREATE
```

The **authoritative scales** (used by every migration in Phase C):

| Family | Steps |
|---|---|
| Type (size) | caption 11 · body 13 · label 15 · title 18 · heading 24 · display 30 |
| Type (weight) | regular w400 · medium w500 · semibold w600 · bold w700 |
| Spacing | 2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 |
| Radius | 4 · 8 · 12 · 16 · 20 · 24 |
| Motion (ms) | fast 120 · base 200 · slow 320 |
| Motion (curve) | standard easeOutCubic · symmetric easeInOut |
| Icon | 16 · 20 · 24 · 32 |
| Glyph (emoji) | react 20 · burst 34 |
| Opacity | dim .60 · scrim .50 · disabled .38 · pressed .12 · hover .08 |

**Snap rule (Phase C):** replace each literal with the token of the nearest scale step. Ties or judgment calls (e.g. a radius equidistant between two steps) resolve toward the neighbor that is already more common in the codebase; record the resulting visual delta and confirm it is within the spec budget (text ≤2px, radius ≤2px, spacing ≤3px). Emoji glyph sizes (20, 34) stay as glyphs, not type.

---

# Phase A — Token files (zero UI change)

## Task 1: Spacing scale

**Files:**
- Create: `lib/core/theme/tokens/spacing.dart`
- Test: `test/core/theme/tokens/spacing_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/spacing.dart';

void main() {
  test('spacing exposes the 8-step scale', () {
    expect(
      [Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl],
      [2, 4, 8, 12, 16, 20, 24, 32],
    );
  });

  test('spacing scale strictly ascends (no duplicates)', () {
    const steps = [Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl];
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]), reason: 'step $i must exceed step ${i - 1}');
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/spacing_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'spacing.dart'` / `Spacing` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Spacing scale (gaps & padding), in logical pixels. Global — identical across
/// all themes. Use instead of bare numbers: `EdgeInsets.all(Spacing.md)`.
abstract final class Spacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/spacing_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens/spacing.dart test/core/theme/tokens/spacing_test.dart
git commit -m "feat: add Spacing token scale"
```

## Task 2: Radius scale

**Files:**
- Create: `lib/core/theme/tokens/radii.dart`
- Test: `test/core/theme/tokens/radii_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/radii.dart';

void main() {
  test('radii exposes the 6-step ladder', () {
    expect(
      [Radii.xs, Radii.sm, Radii.md, Radii.lg, Radii.xl, Radii.pill],
      [4, 8, 12, 16, 20, 24],
    );
  });

  test('radius ladder strictly ascends', () {
    const steps = [Radii.xs, Radii.sm, Radii.md, Radii.lg, Radii.xl, Radii.pill];
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]));
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/radii_test.dart`
Expected: FAIL — `Radii` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Corner-radius ladder, in logical pixels. Global across themes.
/// Use: `BorderRadius.circular(Radii.lg)`.
abstract final class Radii {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 24;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/radii_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens/radii.dart test/core/theme/tokens/radii_test.dart
git commit -m "feat: add Radii token ladder"
```

## Task 3: Motion tokens

**Files:**
- Create: `lib/core/theme/tokens/motion.dart`
- Test: `test/core/theme/tokens/motion_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/motion.dart';

void main() {
  test('durations ascend fast < base < slow', () {
    expect(Motion.fast, const Duration(milliseconds: 120));
    expect(Motion.base, const Duration(milliseconds: 200));
    expect(Motion.slow, const Duration(milliseconds: 320));
    expect(Motion.fast < Motion.base, isTrue);
    expect(Motion.base < Motion.slow, isTrue);
  });

  test('curves are the two standard easings', () {
    expect(Motion.standard, Curves.easeOutCubic);
    expect(Motion.symmetric, Curves.easeInOut);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/motion_test.dart`
Expected: FAIL — `Motion` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/animation.dart';

/// Animation speeds + easings. Global across themes.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve symmetric = Curves.easeInOut;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/motion_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens/motion.dart test/core/theme/tokens/motion_test.dart
git commit -m "feat: add Motion tokens"
```

## Task 4: Icon + glyph sizes

**Files:**
- Create: `lib/core/theme/tokens/icon_sizes.dart`
- Test: `test/core/theme/tokens/icon_sizes_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/icon_sizes.dart';

void main() {
  test('icon sizes ascend', () {
    expect([IconSizes.sm, IconSizes.md, IconSizes.lg, IconSizes.xl], [16, 20, 24, 32]);
  });

  test('emoji glyph sizes are distinct from icon sizes', () {
    expect(Glyphs.react, 20);
    expect(Glyphs.burst, 34);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/icon_sizes_test.dart`
Expected: FAIL — `IconSizes` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Icon sizes (Material icons). Global across themes.
abstract final class IconSizes {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
}

/// Emoji glyph sizes (reactions). Kept separate from text + icons.
abstract final class Glyphs {
  static const double react = 20;
  static const double burst = 34;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/icon_sizes_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens/icon_sizes.dart test/core/theme/tokens/icon_sizes_test.dart
git commit -m "feat: add IconSizes + Glyphs tokens"
```

## Task 5: Opacity levels

**Files:**
- Create: `lib/core/theme/tokens/opacities.dart`
- Test: `test/core/theme/tokens/opacities_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/opacities.dart';

void main() {
  test('opacity levels have the agreed values', () {
    expect(Opacities.dim, 0.60);
    expect(Opacities.scrim, 0.50);
    expect(Opacities.disabled, 0.38);
    expect(Opacities.pressed, 0.12);
    expect(Opacities.hover, 0.08);
  });

  test('every level is a valid alpha in (0, 1]', () {
    for (final a in [Opacities.dim, Opacities.scrim, Opacities.disabled, Opacities.pressed, Opacities.hover]) {
      expect(a, greaterThan(0));
      expect(a, lessThanOrEqualTo(1));
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/opacities_test.dart`
Expected: FAIL — `Opacities` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Named opacity levels for standalone alpha applications. Global across themes.
/// `dim` mirrors MeowColors.textDim's alpha (0x99 ≈ 0.60) for consistency.
abstract final class Opacities {
  static const double dim = 0.60;
  static const double scrim = 0.50;
  static const double disabled = 0.38;
  static const double pressed = 0.12;
  static const double hover = 0.08;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/opacities_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens/opacities.dart test/core/theme/tokens/opacities_test.dart
git commit -m "feat: add Opacities tokens"
```

## Task 6: Shadow tokens (scrim-derived)

**Files:**
- Create: `lib/core/theme/tokens/shadows.dart`
- Test: `test/core/theme/tokens/shadows_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/shadows.dart';

void main() {
  const black = Color(0xFF000000);

  test('card shadow geometry + scrim-derived color', () {
    final s = Shadows.card(black).single;
    expect(s.blurRadius, 16);
    expect(s.offset, const Offset(0, 4));
    expect(s.color.a, closeTo(0.45, 0.01)); // alpha channel as 0..1 double
  });

  test('overlay shadow is heavier than card', () {
    final card = Shadows.card(black).single;
    final overlay = Shadows.overlay(black).single;
    expect(overlay.blurRadius, greaterThan(card.blurRadius));
    expect(overlay.offset.dy, greaterThan(card.offset.dy));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/shadows_test.dart`
Expected: FAIL — `Shadows` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/painting.dart';

/// Drop shadows. Geometry is global; color derives from the active theme's
/// scrim so shadows read correctly on every theme. Pass `context.meow.scrim`.
abstract final class Shadows {
  static List<BoxShadow> card(Color scrim) => [
        BoxShadow(
          color: scrim.withValues(alpha: 0.45),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> overlay(Color scrim) => [
        BoxShadow(
          color: scrim.withValues(alpha: 0.60),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/shadows_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens/shadows.dart test/core/theme/tokens/shadows_test.dart
git commit -m "feat: add scrim-derived Shadow tokens"
```

## Task 7: Type scale (sizes + weights, no color)

**Files:**
- Create: `lib/core/theme/tokens/type_scale.dart`
- Test: `test/core/theme/tokens/type_scale_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/type_scale.dart';

void main() {
  test('type sizes ascend caption..display', () {
    const sizes = [
      TypeScale.caption, TypeScale.body, TypeScale.label,
      TypeScale.title, TypeScale.heading, TypeScale.display,
    ];
    expect(sizes, [11, 13, 15, 18, 24, 30]);
    for (var i = 1; i < sizes.length; i++) {
      expect(sizes[i], greaterThan(sizes[i - 1]));
    }
  });

  test('weights cover the four used roles', () {
    expect(TypeScale.regular, FontWeight.w400);
    expect(TypeScale.medium, FontWeight.w500);
    expect(TypeScale.semibold, FontWeight.w600);
    expect(TypeScale.bold, FontWeight.w700);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/type_scale_test.dart`
Expected: FAIL — `TypeScale` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/painting.dart' show FontWeight;

/// Type scale: font sizes + weights only (no color/family — those come from the
/// active theme via context.meowText). Global across themes.
abstract final class TypeScale {
  static const double caption = 11;
  static const double body = 13;
  static const double label = 15;
  static const double title = 18;
  static const double heading = 24;
  static const double display = 30;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/tokens/type_scale_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/tokens/type_scale.dart test/core/theme/tokens/type_scale_test.dart
git commit -m "feat: add TypeScale sizes + weights"
```

## Task 8: `context.meowText` — the type↔theme seam

This is the one piece of real logic: it composes a global `TypeScale` size/weight with the active theme's color (`MeowColors.textPrimary`) and `titleFontFamily` (Noir's serif on `title`/`heading`/`display`).

**Files:**
- Create: `lib/core/theme/meow_text.dart`
- Test: `test/core/theme/meow_text_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart'; // themeDataFor + context.meow live here
import 'package:meowwatch/core/theme/meow_text.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/theme/tokens/type_scale.dart';

Future<TextStyle> _styleUnder(WidgetTester tester, MeowThemeId id, TextStyle Function(BuildContext) pick) async {
  late TextStyle s;
  await tester.pumpWidget(MaterialApp(
    theme: themeDataFor(id),
    home: Builder(builder: (ctx) {
      s = pick(ctx);
      return const SizedBox();
    }),
  ));
  return s;
}

void main() {
  testWidgets('body uses scale size + theme primary color, no title font', (tester) async {
    final s = await _styleUnder(tester, MeowThemeId.cozy, (c) => c.meowText.body);
    expect(s.fontSize, TypeScale.body); // 13
    expect(s.color, MeowColors.cozy.textPrimary);
    expect(s.fontFamily, isNull);
  });

  testWidgets('title picks up Noir serif via titleFontFamily', (tester) async {
    final s = await _styleUnder(tester, MeowThemeId.noir, (c) => c.meowText.title);
    expect(s.fontSize, TypeScale.title); // 18
    expect(s.fontFamily, 'serif');
    expect(s.color, MeowColors.noir.textPrimary);
  });

  testWidgets('caption has no title font on Noir (not a heading)', (tester) async {
    final s = await _styleUnder(tester, MeowThemeId.noir, (c) => c.meowText.caption);
    expect(s.fontFamily, isNull);
  });
}
```

> NOTE: `themeDataFor(MeowThemeId)` is declared in `lib/core/theme/meow_context.dart` (confirmed), so importing that file covers both `themeDataFor` and the `context.meow`/`context.meowText` extensions.

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/meow_text_test.dart`
Expected: FAIL — `meowText` getter undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/material.dart';

import 'meow_context.dart';
import 'meow_theme.dart';
import 'tokens/type_scale.dart';

/// Text styles composed from the global [TypeScale] (size/weight) and the active
/// theme's [MeowColors] (color + titleFontFamily). Access via `context.meowText`.
///
/// Base styles use [MeowColors.textPrimary]; for dim text, call sites apply
/// `.copyWith(color: context.meow.textDim)`. title/heading/display carry the
/// theme's titleFontFamily (serif on Noir); smaller roles do not.
@immutable
class MeowTextStyles {
  const MeowTextStyles(this._c);
  final MeowColors _c;

  TextStyle get caption => TextStyle(
        fontSize: TypeScale.caption,
        fontWeight: TypeScale.regular,
        color: _c.textPrimary,
      );

  TextStyle get body => TextStyle(
        fontSize: TypeScale.body,
        fontWeight: TypeScale.regular,
        color: _c.textPrimary,
      );

  TextStyle get label => TextStyle(
        fontSize: TypeScale.label,
        fontWeight: TypeScale.medium,
        color: _c.textPrimary,
      );

  TextStyle get title => TextStyle(
        fontSize: TypeScale.title,
        fontWeight: TypeScale.semibold,
        color: _c.textPrimary,
        fontFamily: _c.titleFontFamily,
      );

  TextStyle get heading => TextStyle(
        fontSize: TypeScale.heading,
        fontWeight: TypeScale.semibold,
        color: _c.textPrimary,
        fontFamily: _c.titleFontFamily,
      );

  TextStyle get display => TextStyle(
        fontSize: TypeScale.display,
        fontWeight: TypeScale.bold,
        color: _c.textPrimary,
        fontFamily: _c.titleFontFamily,
      );
}

/// `context.meowText.body` — the active theme's composed text styles.
extension MeowTextContext on BuildContext {
  MeowTextStyles get meowText => MeowTextStyles(meow);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/theme/meow_text_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run analyze + full suite (nothing should regress — no UI uses tokens yet)**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: No issues found!
Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/meow_text.dart test/core/theme/meow_text_test.dart
git commit -m "feat: add context.meowText composing TypeScale with theme color/font"
```

---

# Phase B — The gallery

## Task 9: Gallery tap counter (pure logic) — OPTIONAL

> **SKIP this task** if you adopt the recommended **long-press** gallery gesture (Task 13). The tap-counter was the mechanism for the "tap 5×" gesture, which conflicts with the badge's existing single-tap-opens-dialog behavior (see Task 13). Build it only if the user insists on a multi-tap gesture instead of long-press.

Split the "tap 5× within 3s" rule into pure, testable logic (matches the project's pattern of extracting pure logic from widgets, e.g. `sync_follow.dart`).

**Files:**
- Create: `lib/ui/gallery/gallery_tap_counter.dart`
- Test: `test/ui/gallery/gallery_tap_counter_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/gallery/gallery_tap_counter.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  test('fires exactly on the 5th tap within the window, then resets', () {
    final c = GalleryTapCounter();
    expect(c.register(t0), isFalse); // 1
    expect(c.register(t0.add(const Duration(milliseconds: 300))), isFalse); // 2
    expect(c.register(t0.add(const Duration(milliseconds: 600))), isFalse); // 3
    expect(c.register(t0.add(const Duration(milliseconds: 900))), isFalse); // 4
    expect(c.register(t0.add(const Duration(milliseconds: 1200))), isTrue); // 5 -> fire
    // After firing it resets; the next tap is "1" again.
    expect(c.register(t0.add(const Duration(milliseconds: 1300))), isFalse);
  });

  test('a gap longer than the window restarts the count', () {
    final c = GalleryTapCounter();
    c.register(t0);
    c.register(t0.add(const Duration(seconds: 1)));
    // 4 seconds after the previous tap — older taps expire, this is a fresh "1".
    expect(c.register(t0.add(const Duration(seconds: 5))), isFalse);
    expect(c.register(t0.add(const Duration(seconds: 5, milliseconds: 200))), isFalse); // 2
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/gallery/gallery_tap_counter_test.dart`
Expected: FAIL — `GalleryTapCounter` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Counts rapid taps and fires when [threshold] taps land within [window].
/// Time is passed in (no Date.now inside) so it is fully unit-testable.
class GalleryTapCounter {
  GalleryTapCounter({
    this.threshold = 5,
    this.window = const Duration(seconds: 3),
  });

  final int threshold;
  final Duration window;
  final List<DateTime> _taps = <DateTime>[];

  /// Records a tap at [now]; returns true when this tap completes a burst of
  /// [threshold] taps inside [window]. Resets after firing.
  bool register(DateTime now) {
    _taps
      ..removeWhere((t) => now.difference(t) > window)
      ..add(now);
    if (_taps.length >= threshold) {
      _taps.clear();
      return true;
    }
    return false;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/gallery/gallery_tap_counter_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/gallery/gallery_tap_counter.dart test/ui/gallery/gallery_tap_counter_test.dart
git commit -m "feat: add GalleryTapCounter burst-tap logic"
```

## Task 10: Gallery sections (specimens + component zoo)

Build the specimen widgets. Each renders one scale; the zoo renders real components so a future token edit ripples visibly. No new test (it is pure presentation, exercised via a smoke pump in Task 11).

**Files:**
- Create: `lib/ui/gallery/gallery_sections.dart`

- [ ] **Step 1: Implement the section widgets**

```dart
import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/opacities.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/shadows.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';

/// A titled block with a small uppercase header.
class GallerySection extends StatelessWidget {
  const GallerySection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: context.meowText.caption.copyWith(
                color: c.accent,
                letterSpacing: 1.5,
                fontWeight: TypeScale.semibold,
              )),
          const SizedBox(height: Spacing.sm),
          child,
        ],
      ),
    );
  }
}

class TypeSpecimen extends StatelessWidget {
  const TypeSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.meowText;
    final rows = <(String, TextStyle)>[
      ('caption 11', t.caption),
      ('body 13', t.body),
      ('label 15', t.label),
      ('title 18', t.title),
      ('heading 24', t.heading),
      ('display 30', t.display),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (name, style) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(width: 96, child: Text(name, style: t.caption.copyWith(color: context.meow.textDim))),
                const SizedBox(width: Spacing.md),
                Text('The quick brown fox', style: style),
              ],
            ),
          ),
      ],
    );
  }
}

class RadiusSpecimen extends StatelessWidget {
  const RadiusSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final steps = <(String, double)>[
      ('xs', Radii.xs), ('sm', Radii.sm), ('md', Radii.md),
      ('lg', Radii.lg), ('xl', Radii.xl), ('pill', Radii.pill),
    ];
    return Wrap(spacing: Spacing.lg, runSpacing: Spacing.md, children: [
      for (final (name, r) in steps)
        Column(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: c.myBubble,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(r),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text('$name ${r.toInt()}', style: context.meowText.caption.copyWith(color: c.textDim)),
        ]),
    ]);
  }
}

class SpacingSpecimen extends StatelessWidget {
  const SpacingSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    const steps = <double>[
      Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md,
      Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl,
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final s in steps)
        Padding(
          padding: const EdgeInsets.only(right: Spacing.md),
          child: Column(children: [
            Container(width: s, height: 32, color: c.accent),
            const SizedBox(height: Spacing.xs),
            Text(s.toInt().toString(), style: context.meowText.caption.copyWith(color: c.textDim)),
          ]),
        ),
    ]);
  }
}

class IconSpecimen extends StatelessWidget {
  const IconSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final steps = <(String, double)>[
      ('16', IconSizes.sm), ('20', IconSizes.md), ('24', IconSizes.lg), ('32', IconSizes.xl),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final (name, s) in steps)
        Padding(
          padding: const EdgeInsets.only(right: Spacing.lg),
          child: Column(children: [
            Icon(Icons.pets, size: s, color: c.accent),
            Text(name, style: context.meowText.caption.copyWith(color: c.textDim)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(left: Spacing.md),
        child: Column(children: [
          Text('🐾', style: TextStyle(fontSize: Glyphs.react)),
          Text('react 20', style: context.meowText.caption.copyWith(color: c.textDim)),
        ]),
      ),
      Column(children: [
        Text('🐾', style: TextStyle(fontSize: Glyphs.burst)),
        Text('burst 34', style: context.meowText.caption.copyWith(color: c.textDim)),
      ]),
    ]);
  }
}

class OpacitySpecimen extends StatelessWidget {
  const OpacitySpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final steps = <(String, double)>[
      ('dim', Opacities.dim), ('scrim', Opacities.scrim),
      ('disabled', Opacities.disabled), ('pressed', Opacities.pressed), ('hover', Opacities.hover),
    ];
    return Wrap(spacing: Spacing.md, runSpacing: Spacing.md, children: [
      for (final (name, a) in steps)
        Column(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: a),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
          ),
          Text(name, style: context.meowText.caption.copyWith(color: c.textDim)),
        ]),
    ]);
  }
}

class MotionAndShadowSpecimen extends StatelessWidget {
  const MotionAndShadowSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    String ms(Duration d) => '${d.inMilliseconds}ms';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('fast ${ms(Motion.fast)} · base ${ms(Motion.base)} · slow ${ms(Motion.slow)}',
          style: context.meowText.body.copyWith(color: c.textDim)),
      const SizedBox(height: Spacing.lg),
      Row(children: [
        Container(width: 80, height: 48,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: Shadows.card(c.scrim))),
        const SizedBox(width: Spacing.xxl),
        Container(width: 80, height: 48,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: Shadows.overlay(c.scrim))),
      ]),
    ]);
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze lib/ui/gallery/gallery_sections.dart`
Expected: No issues found!

- [ ] **Step 3: Commit**

```bash
git add lib/ui/gallery/gallery_sections.dart
git commit -m "feat: add design gallery specimen widgets"
```

## Task 11: Gallery screen + theme switcher + smoke test

**Files:**
- Create: `lib/ui/gallery/design_gallery.dart`
- Test: `test/ui/gallery/design_gallery_test.dart`

- [ ] **Step 1: Write the failing smoke test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/gallery/design_gallery.dart';

void main() {
  testWidgets('gallery renders and switches theme without throwing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    expect(find.text('TYPOGRAPHY'), findsOneWidget);

    // Switch to Cinema Noir via its label chip.
    await tester.tap(find.text(MeowThemeId.noir.label));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/gallery/design_gallery_test.dart`
Expected: FAIL — `DesignGallery` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/tokens/spacing.dart';
import 'gallery_sections.dart';

/// Hidden design-system gallery: every token scale + the live component zoo,
/// switchable across all three themes. Reachable only via the version-badge
/// long-press or MEOWWATCH_GALLERY=1 (see version_badge.dart / main.dart).
class DesignGallery extends StatefulWidget {
  const DesignGallery({super.key});
  @override
  State<DesignGallery> createState() => _DesignGalleryState();
}

class _DesignGalleryState extends State<DesignGallery> {
  MeowThemeId _id = MeowThemeId.cozy;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: themeDataFor(_id),
      child: Builder(builder: (context) {
        final c = context.meow;
        return Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.surface,
            foregroundColor: c.textPrimary,
            title: const Text('Design Gallery'),
            actions: [
              for (final id in MeowThemeId.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: Spacing.sm),
                  child: ChoiceChip(
                    label: Text(id.label),
                    selected: _id == id,
                    onSelected: (_) => setState(() => _id = id),
                  ),
                ),
              const SizedBox(width: Spacing.md),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(Spacing.xl),
            children: const [
              GallerySection(title: 'Typography', child: TypeSpecimen()),
              GallerySection(title: 'Radius', child: RadiusSpecimen()),
              GallerySection(title: 'Spacing', child: SpacingSpecimen()),
              GallerySection(title: 'Icon / Glyph', child: IconSpecimen()),
              GallerySection(title: 'Opacity', child: OpacitySpecimen()),
              GallerySection(title: 'Motion + Shadow', child: MotionAndShadowSpecimen()),
              // Component zoo is appended in Task 12.
            ],
          ),
        );
      }),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/gallery/design_gallery_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/gallery/design_gallery.dart test/ui/gallery/design_gallery_test.dart
git commit -m "feat: add DesignGallery screen with live theme switcher"
```

## Task 12: Component zoo in the gallery

Add a section that renders real components so token edits show their true effect. Reuse existing widgets with sample data.

**Files:**
- Modify: `lib/ui/gallery/gallery_sections.dart` (add `ComponentZoo`)
- Modify: `lib/ui/gallery/design_gallery.dart` (mount it)

Confirmed constructor signatures (already read — do not re-guess):
- `ChatBubble({required ChatMessage message, required String myUsername})` — `lib/ui/chat/chat_bubble.dart`
- `ChatMessage({required String username, required String text, DateTime? timestamp, bool system = false})` — `lib/core/sync/peer_state.dart`
- `EmptyState({required VoidCallback onBrowse, String? notice})` — `lib/ui/empty_state.dart`

`ChatBubble` renders an "own" bubble when `message.username == myUsername`, otherwise a peer bubble; `system: true` renders a centered event line. That single widget gives us all three bubble states.

- [ ] **Step 1: Add `ComponentZoo` to `gallery_sections.dart`**

Add these imports at the top of `gallery_sections.dart`:

```dart
import '../../core/sync/peer_state.dart';
import '../chat/chat_bubble.dart';
import '../empty_state.dart';
```

Append this widget. `timestamp` uses a fixed literal `DateTime` (never `DateTime.now()` — keep it deterministic so the gallery is reproducible):

```dart
class ComponentZoo extends StatelessWidget {
  const ComponentZoo({super.key});

  @override
  Widget build(BuildContext context) {
    final stamp = DateTime(2026, 1, 1, 21, 4);
    const me = 'you';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // All three bubble states from one widget.
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChatBubble(
                message: ChatMessage(username: 'Mochi', text: 'this part is so good omg', timestamp: stamp),
                myUsername: me,
              ),
              const SizedBox(height: Spacing.xs),
              ChatBubble(
                message: ChatMessage(username: me, text: 'right?? rewinding 10s', timestamp: stamp),
                myUsername: me,
              ),
              const SizedBox(height: Spacing.xs),
              ChatBubble(
                message: const ChatMessage(username: '', text: '🐾 Mochi joined the room', system: true),
                myUsername: me,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),
        // EmptyState fills its parent — give it a bounded box in the gallery list.
        SizedBox(
          height: 220,
          child: EmptyState(onBrowse: () {}, notice: 'lin started playback — load a video to join'),
        ),
      ],
    );
  }
}
```

> Optionally add more components (PeekTab, ReactionBar) the same way — read their constructors first. The two above are enough to prove the token migration. The zoo is presentation-only; its correctness rides on the existing per-component widget tests plus the gallery smoke test.

- [ ] **Step 2: Mount the zoo in `design_gallery.dart`**

`ComponentZoo()` is **not** `const` (it builds a `DateTime` and an `onBrowse` closure), so the `ListView`'s `children: const [...]` from Task 11 can no longer be a `const` list. Drop the `const` keyword on that children list and add the zoo as the last child, after `Motion + Shadow`:

```dart
body: ListView(
  padding: const EdgeInsets.all(Spacing.xl),
  children: [
    const GallerySection(title: 'Typography', child: TypeSpecimen()),
    const GallerySection(title: 'Radius', child: RadiusSpecimen()),
    const GallerySection(title: 'Spacing', child: SpacingSpecimen()),
    const GallerySection(title: 'Icon / Glyph', child: IconSpecimen()),
    const GallerySection(title: 'Opacity', child: OpacitySpecimen()),
    const GallerySection(title: 'Motion + Shadow', child: MotionAndShadowSpecimen()),
    const GallerySection(title: 'Components', child: ComponentZoo()),
  ],
),
```

(`GallerySection` and `ComponentZoo` both have `const` constructors — `const GallerySection(title: 'Components', child: ComponentZoo())` is valid because `ComponentZoo`'s own const-ness is independent of the `DateTime` it builds at runtime in `build()`. The list itself stays non-`const` only if you prefer; the per-item `const` above is fine. If analyze flags a `const` issue, remove the offending `const`.)

- [ ] **Step 3: Extend the smoke test**

Add to `test/ui/gallery/design_gallery_test.dart`:

```dart
testWidgets('component zoo renders', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
  expect(find.text('COMPONENTS'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 4: Run analyze + the gallery tests**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: No issues found!
Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/gallery/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/gallery/gallery_sections.dart lib/ui/gallery/design_gallery.dart test/ui/gallery/design_gallery_test.dart
git commit -m "feat: add live component zoo to design gallery"
```

## Task 13: Wire access — version-badge long-press + env-var backup

> **Discovered conflict (resolved here):** the badge already opens the `UpdateDialog` on **single tap** (`InkWell(onTap: _openDialog)` in `_VersionBadgeState.build`), and it lives on the Connect screen. A 5×-tap gesture (the brainstorm choice) cannot work — the first tap pops a modal dialog that covers the badge, so taps 2–5 never land. **Resolution: open the gallery on `onLongPress`** of the same `InkWell`. Single-tap → update dialog stays exactly as-is; long-press → gallery; no conflict, no debounce, no accidental triggers. (This means **Task 9's `GalleryTapCounter` is not used** — it was the 5×-tap mechanism; skip Task 9, or keep it harmlessly. Confirm this substitution with the user before implementing — it deviates from the approved "tap 5×".)

**Files:**
- Modify: `lib/ui/version_badge.dart`
- Modify: the first screen's wiring for the env var (`lib/main.dart` / `lib/app.dart` / connect screen — read to decide)
- Test: `test/ui/version_badge_test.dart` (extend)

- [ ] **Step 1: Read how existing badge tests pump the widget**

Read `test/ui/version_badge_test.dart`. The badge does a once-per-session network check in `initState`; existing tests pass `VersionBadge(serviceFactory: ...)` backed by a mock so it never hits the network and call `VersionBadge.resetForTest()` between tests. **Reuse that exact construction** in the new test below — do not pump a bare `VersionBadge()` (it would attempt a real check).

- [ ] **Step 2: Write the failing test (long-press opens the gallery)**

Add to `test/ui/version_badge_test.dart`, mirroring the existing tests' mock `serviceFactory` and `resetForTest()` setup:

```dart
testWidgets('long-pressing the version badge opens the DesignGallery', (tester) async {
  VersionBadge.resetForTest();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: VersionBadge(serviceFactory: () => /* the mock factory used by existing tests */),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  await tester.longPress(find.byType(VersionBadge));
  await tester.pumpAndSettle();

  expect(find.byType(DesignGallery), findsOneWidget);
});
```

Add import: `import 'package:meowwatch/ui/gallery/design_gallery.dart';`

- [ ] **Step 3: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/version_badge_test.dart -p "long-press"`
Expected: FAIL — no `DesignGallery` is pushed (no long-press handler yet).

- [ ] **Step 4: Add `onLongPress` to the existing InkWell in `version_badge.dart`**

Add the import and a handler, and wire `onLongPress` on the `InkWell` that already exists in `build` (keep `onTap: _openDialog` untouched):

```dart
import 'gallery/design_gallery.dart';

// in _VersionBadgeState:
void _openGallery() {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const DesignGallery()),
  );
}

// in build(), on the existing InkWell:
child: InkWell(
  borderRadius: BorderRadius.circular(12),
  onTap: _openDialog,
  onLongPress: _openGallery,   // <-- the only addition
  child: Container(/* unchanged */),
),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/version_badge_test.dart`
Expected: PASS (existing tests + the new long-press test).

- [ ] **Step 6: Add the env-var backup door**

Read `lib/main.dart` and `lib/app.dart` to see how the first screen is chosen and whether a global navigator key exists. Then add a one-time, guarded open of the gallery when `MEOWWATCH_GALLERY=1`:

- **If a global navigator key exists:** after first frame, `nav.push(MaterialPageRoute(builder: (_) => const DesignGallery()))`.
- **If not (likely):** gate it in the first screen's `initState` (the connect screen), pushing once after the first frame:

```dart
// dart:io import needed for Platform.
@override
void initState() {
  super.initState();
  if (Platform.environment['MEOWWATCH_GALLERY'] == '1') {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DesignGallery()),
      );
    });
  }
}
```

Do not invent a navigator key if one is not already there — prefer the `initState` route.

- [ ] **Step 7: analyze + full suite**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: No issues found!
Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/version_badge.dart lib/main.dart lib/app.dart test/ui/version_badge_test.dart
git commit -m "feat: open design gallery via badge long-press + MEOWWATCH_GALLERY env"
```

---

# Phase C — Migrate UI files onto the tokens

**Procedure for every migration task below:**
1. Replace each literal with the nearest token per the **authoritative scales** + **snap rule** at the top of this plan. Imports: add the specific token files used (`spacing.dart`, `radii.dart`, etc.) and, for text, replace `TextStyle(fontSize: N, ...)` with `context.meowText.<role>` (apply `.copyWith(color: context.meow.textDim)` etc. where the old code set a non-primary color/weight).
2. `$FLUTTER analyze` → No issues found!
3. Run that file's widget test(s); fix any test that asserts an exact pre-migration pixel so it references the token (not by loosening the assertion blindly — update it to the new intended value).
4. If the widget has a golden (only chat overlay + idle mascot do), regenerate with `--update-goldens` and **open the PNG to confirm only the intended ≤2px shift changed** (CLAUDE.md gotcha).
5. Commit per area.

**Golden map (only these regen):**
- `test/ui/chat/chat_overlay_golden_test.dart` → `chat_overlay_empty.png`, `chat_overlay_expanded.png` (Task 14)
- `test/ui/idle_mascot_golden_test.dart` → `idle_mascot.png` (Task 18, only if the mascot's values are touched)

## Task 14: Migrate chat widgets

**Files (modify):** `lib/ui/chat/chat_bubble.dart`, `lib/ui/chat/chat_overlay.dart`, `lib/ui/chat/chat_input.dart`, `lib/ui/chat/peek_tab.dart`
**Tests:** `chat_bubble_test.dart`, `chat_input_test.dart`, `peek_tab_test.dart`, `chat_overlay_*_test.dart` (incl. the `chat_overlay_repaint_test.dart` guard), `chat_overlay_golden_test.dart`

Literal → token map for this area (from the audit):

| File | Literal | Token |
|---|---|---|
| chat_bubble | fontSize 11 (name, w600) | `meowText.caption.copyWith(fontWeight: TypeScale.semibold)` |
| chat_bubble | fontSize 14 (body) | `meowText.body` (13; role wins, −1) |
| chat_bubble | fontSize 11 / 10 (meta) | `meowText.caption` (10→11) |
| chat_bubble | `BorderRadius.circular(14)` | `Radii.lg` (16) |
| peek_tab | fontSize 9 (bold) | `meowText.caption.copyWith(fontWeight: TypeScale.bold)` (9→11) |
| chat_input | fontSize 11 / 14 | `meowText.caption` / `meowText.label` (14→15) |
| chat_overlay | fontSize 13 ×2, 12, 11 ×2 | `meowText.body` (12→13) / `meowText.caption` |
| chat_overlay | fontWeight.bold labels | `.copyWith(fontWeight: TypeScale.bold)` |
| chat_overlay | `BorderRadius.circular(16)` ×4 | `Radii.lg` |
| chat_overlay | header `EdgeInsets.only(left: 24, right: 12)` (#76) | `EdgeInsets.only(left: Spacing.xxl, right: Spacing.md)` — both exact |
| all | `EdgeInsets`/`SizedBox` numbers | nearest `Spacing.*` |
| all | `Duration(milliseconds: …)`, `Curves.*` | nearest `Motion.*` |

> **#76 coupling caution:** the header's `left: 24` inset is deliberately tuned to clear the **22px top-left resize grip** (`_grip`) so the move-drag icon doesn't overlap the resize Listener. 24 maps cleanly to `Spacing.xxl`; the grip's **22** is NOT a scale step — **leave the 22px grip bespoke** (don't snap it to 20 or 24), or the header-clears-grip invariant breaks. If you do touch the grip, keep `grip ≤ header-left-inset`. Re-run `chat_overlay_resize_test.dart` after this file.

- [ ] **Step 1:** Apply the map above across the four files. Keep behavior identical; only swap literals for tokens. Run `chat_overlay_resize_test.dart` as part of Step 3 (the grip/resize path).
- [ ] **Step 2:** `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze` → No issues found!
- [ ] **Step 3:** Run chat widget tests (non-golden):
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_bubble_test.dart test/ui/chat/chat_input_test.dart test/ui/chat/peek_tab_test.dart test/ui/chat/chat_overlay_test.dart test/ui/chat/chat_overlay_repaint_test.dart test/ui/chat/chat_overlay_resize_test.dart`
  Fix any exact-pixel assertions to the new token value. The repaint guard MUST stay green; the resize test guards the #76 grip coupling.
- [ ] **Step 4:** Regenerate + inspect goldens:
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_overlay_golden_test.dart --update-goldens`
  Open `test/ui/chat/goldens/chat_overlay_empty.png` and `chat_overlay_expanded.png`; confirm only the intended small shifts (text +/-1px, corner 16) are visible — no layout breakage, no white wash.
- [ ] **Step 5:** Re-run the golden test without the flag to confirm it passes:
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/chat/chat_overlay_golden_test.dart`
  Expected: PASS.
- [ ] **Step 6:** Commit
```bash
git add lib/ui/chat test/ui/chat
git commit -m "refactor: migrate chat widgets to design tokens"
```

## Task 15: Migrate the connect screen

**Files (modify):** `lib/ui/connect/connect_screen.dart` (and `lib/ui/connect/history_format.dart` only if it carries style literals — it is mostly pure formatting; check)
**Tests:** `connect_screen_test.dart`, `history_format_test.dart`

Key literals: fontSize 30 (title, w600) → `meowText.display`; fontSize 14 → `meowText.label`; fontSize 12/13 → `meowText.body`; `FontWeight.w700` (code) → `.copyWith(fontWeight: TypeScale.bold)`; `BorderRadius.circular(10/12)` → `Radii.sm`/`Radii.md` (10→12 per snap, or 10→8 if it reads better — inspect); `BorderRadius.circular(3)` → `Radii.xs` (3→4); `EdgeInsets`/`SizedBox` → nearest `Spacing.*`; `size:` icon values → nearest `IconSizes.*`.

- [ ] **Step 1:** Apply tokens across the connect screen.
- [ ] **Step 2:** `…/flutter.bat analyze` → No issues found!
- [ ] **Step 3:** `…/flutter.bat test test/ui/connect/` → fix any pixel assertions; all pass.
- [ ] **Step 4:** Commit
```bash
git add lib/ui/connect test/ui/connect
git commit -m "refactor: migrate connect screen to design tokens"
```

## Task 16: Migrate the player gear menu + version badge visuals

**Files (modify):** `lib/ui/player_menu_button.dart`, `lib/ui/version_badge.dart` (visual literals only — the gesture from Task 13 stays)
**Tests:** `player_menu_button_test.dart`, `player_menu_sound_picker_test.dart`, `version_badge_test.dart`

Key literals: fontSize 13/14/15/18 → `meowText.body`/`label`/`label`/`title`; many `BorderRadius.circular(10/14/20/8)` → `Radii.sm/lg/xl/sm`; `EdgeInsets`/`SizedBox` → `Spacing.*`; `Duration`/`Curves.easeInOut`/`easeOutCubic` → `Motion.base`/`Motion.symmetric`/`Motion.standard`; icon `size:` → `IconSizes.*`; version_badge fontSize 11 (w500) → `meowText.caption.copyWith(fontWeight: TypeScale.medium)`, `BorderRadius.circular(12)` → `Radii.md`.

- [ ] **Step 1:** Apply tokens.
- [ ] **Step 2:** analyze → clean.
- [ ] **Step 3:** `…/flutter.bat test test/ui/player_menu_button_test.dart test/ui/player_menu_sound_picker_test.dart test/ui/version_badge_test.dart` → fix pixel assertions; all pass.
- [ ] **Step 4:** Commit
```bash
git add lib/ui/player_menu_button.dart lib/ui/version_badge.dart test/ui/player_menu_button_test.dart test/ui/player_menu_sound_picker_test.dart test/ui/version_badge_test.dart
git commit -m "refactor: migrate player menu + version badge to design tokens"
```

## Task 17: Migrate dialogs + HUD overlays

**Files (modify):** `lib/ui/update_dialog.dart`, `lib/ui/window_close_handler.dart`, `lib/ui/empty_state.dart`, `lib/ui/seek_indicator.dart`, `lib/ui/volume_indicator.dart`, `lib/ui/action_feedback_overlay.dart`, `lib/ui/playback_bar.dart`
**Tests:** `update_dialog_test.dart`, `window_close_handler_test.dart`, `empty_state_test.dart`, `playback_bar_test.dart` (others have no dedicated test — rely on analyze + the gallery zoo)

Key literals: fontSize 11/12/13/14/15/17/18 → roles (`caption`/`body`/`label`/`title`; 17→18, 12→13, 14→15); `BorderRadius.circular(16/8/4/14/3)` → `Radii.lg/sm/xs/lg/xs` (14→16, 3→4); `EdgeInsets`/`SizedBox` → `Spacing.*`; `size:` → `IconSizes.*`; `BoxShadow` in version/overlay → `Shadows.card(context.meow.scrim)` / `Shadows.overlay(...)`.

- [ ] **Step 1:** Apply tokens across the seven files.
- [ ] **Step 2:** analyze → clean.
- [ ] **Step 3:** `…/flutter.bat test test/ui/update_dialog_test.dart test/ui/window_close_handler_test.dart test/ui/empty_state_test.dart test/ui/playback_bar_test.dart` → fix pixel assertions; all pass.
- [ ] **Step 4:** Commit
```bash
git add lib/ui/update_dialog.dart lib/ui/window_close_handler.dart lib/ui/empty_state.dart lib/ui/seek_indicator.dart lib/ui/volume_indicator.dart lib/ui/action_feedback_overlay.dart lib/ui/playback_bar.dart test/ui
git commit -m "refactor: migrate dialogs + HUD overlays to design tokens"
```

## Task 18: Migrate reactions, home screen, remaining painters

**Files (modify):** `lib/ui/reactions/reaction_bar.dart`, `lib/ui/reactions/floating_reactions.dart`, `lib/ui/home_screen.dart`, `lib/ui/video_surface.dart`, `lib/ui/idle_mascot.dart`
**Tests:** `reaction_bar_test.dart`, `floating_reactions_test.dart`, `idle_mascot_test.dart`, `idle_mascot_golden_test.dart`

Key literals: reaction_bar fontSize 20 → `Glyphs.react`, `BorderRadius.circular(24)` → `Radii.pill`, `Curves.easeOut`→`Motion.standard`; floating_reactions fontSize 34 → `Glyphs.burst`; home_screen fontSize 14 → `meowText.label`, `BorderRadius.circular(20)` → `Radii.xl`, `Duration` → `Motion.*`; video_surface `Duration` → `Motion.*`.

**Painters caution (idle_mascot, floating_reactions):** these use bespoke `withValues(alpha:)` for drawing. Only swap an alpha for an `Opacities.*` token **if the value already equals a token** (e.g. 0.6 → `Opacities.dim`). If a painter's alpha is a custom value that does not match a token, **leave it as-is** — do not snap painter alphas (it would change the art and churn the golden for no system benefit). Same for any custom mascot dimensions.

- [ ] **Step 1:** Apply tokens; obey the painter caution above.
- [ ] **Step 2:** analyze → clean.
- [ ] **Step 3:** `…/flutter.bat test test/ui/reactions/ test/ui/idle_mascot_test.dart` → fix pixel assertions; all pass.
- [ ] **Step 4:** Only if `idle_mascot.dart` visual values changed: regenerate + inspect its golden:
  `…/flutter.bat test test/ui/idle_mascot_golden_test.dart --update-goldens` → open `test/ui/goldens/idle_mascot.png`, confirm unchanged/intended. If you left the mascot's bespoke values alone, the golden should still pass WITHOUT regeneration — run it without the flag to confirm:
  `…/flutter.bat test test/ui/idle_mascot_golden_test.dart`
- [ ] **Step 5:** Commit
```bash
git add lib/ui/reactions lib/ui/home_screen.dart lib/ui/video_surface.dart lib/ui/idle_mascot.dart test/ui
git commit -m "refactor: migrate reactions, home, painters to design tokens"
```

## Task 19: Sweep for stragglers

- [ ] **Step 1:** Re-run the audit greps to confirm only intentional literals remain (gallery specimens legitimately contain numbers; painters keep bespoke values):

```bash
grep -rnE "fontSize:\s*[0-9]" lib/ui --include=*.dart | grep -v gallery
grep -rnE "BorderRadius\.circular\([0-9]" lib/ui --include=*.dart | grep -v gallery
```
Expected: only painter/gallery lines, no plain widget literals. Convert any stragglers found.

- [ ] **Step 2:** Full suite + analyze:
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze` → No issues found!
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test` → all pass.

- [ ] **Step 3:** Commit (if anything changed)
```bash
git add lib test
git commit -m "refactor: convert remaining straggler literals to tokens"
```

---

# Phase D — Version, changelog, manual verification

## Task 20: Version bump + changelog

**Files:** `pubspec.yaml`, `lib/core/app_version.dart`, `CHANGELOG.md`

- [ ] **Step 1:** Read current values to confirm the from-version.
  Read `pubspec.yaml` (`version:`) and `lib/core/app_version.dart` (`appVersion`). Expected current: `0.14.0-alpha` (pubspec shows `0.14.0-alpha+1`) — PR #76 already shipped 0.14.0, so the design system is the **next** MINOR.

- [ ] **Step 2:** Bump all three to `0.15.0-alpha` (MINOR — a `feat:`).
  - `pubspec.yaml`: `version: 0.15.0-alpha+1` (keep the existing `+1` build-suffix convention).
  - `lib/core/app_version.dart`: `appVersion = '0.15.0-alpha'`.
  - `CHANGELOG.md`: add a new top entry:

```markdown
## [0.15.0-alpha] - 2026-06-03

### Added
- Design-system token scales (type, spacing, radius, motion, icon/glyph, opacity, shadow) under `lib/core/theme/tokens/`, plus a `context.meowText` helper composing type with the active theme.
- Hidden in-app design gallery showing every token + live components across all 3 themes (open via **long-pressing** the version badge, or `MEOWWATCH_GALLERY=1`).

### Changed
- Migrated all UI widgets off hand-typed sizes onto the token scales; a handful of values snapped to the nearest scale step (text/radius ≤2px, spacing ≤3px).
```

- [ ] **Step 3:** analyze + full suite:
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze` → No issues found!
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test` → all pass.

- [ ] **Step 4:** Commit
```bash
git add pubspec.yaml lib/core/app_version.dart CHANGELOG.md
git commit -m "chore: bump to 0.15.0-alpha (design system)"
```

## Task 21: Manual two-instance Release verification

This is a visible change, so a manual pass is warranted before tagging (per CLAUDE.md release flow). **Get the user's confirmation that the manual test passes before considering the work done.**

- [ ] **Step 1:** Kill running instances (file lock): `Stop-Process -Name meowwatch -Force` (ignore "not found").
- [ ] **Step 2:** Build Release:
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat build windows`
  Confirm `build/windows/x64/runner/Release/data/app.so` mtime updated (Dart changes land there, not in the `.exe`).
- [ ] **Step 3:** For two-instance-on-one-PC, set `$env:MEOWWATCH_FORCE_SW_DECODE='1'` before launching each instance (HW-decode contention gotcha).
- [ ] **Step 4:** Manually verify: app looks right across all three themes (switch via the gear menu); chat bubbles, connect screen, dialogs, reactions render correctly; open the gallery (long-press the version badge on the Connect screen) and eyeball every scale + the component zoo in each theme; confirm no white-wash flash when dragging the chat overlay (#50 guard).
- [ ] **Step 5:** Report results to the user. If anything looks off, fix before proceeding to the release flow (PR → CI → tag) described in CLAUDE.md.

---

## Self-review notes (author)

- **Spec coverage:** all 7 families → Tasks 1–7; `meowText` seam → Task 8; gallery (scales + zoo + theme switch + hidden access) → Tasks 9–13; rationalize/snap with ≤2px budget → Phase C procedure + per-task maps; goldens regenerated+inspected → Tasks 14/18; unit tests for scale shape → Tasks 1–7; version bump → Task 20; manual Release check → Task 21. No spec requirement left without a task.
- **Token names are stable across tasks:** `Spacing.{xxs,xs,sm,md,lg,xl,xxl,xxxl}`, `Radii.{xs,sm,md,lg,xl,pill}`, `Motion.{fast,base,slow,standard,symmetric}`, `IconSizes.{sm,md,lg,xl}`, `Glyphs.{react,burst}`, `Opacities.{dim,scrim,disabled,pressed,hover}`, `TypeScale.{caption,body,label,title,heading,display}`+`{regular,medium,semibold,bold}`, `Shadows.{card,overlay}`, `context.meowText.{caption,body,label,title,heading,display}` — referenced identically in Phases B/C.
- **Known soft spots flagged inline for the implementer:** exact `themeDataFor` import location (Task 8), the version-badge existing-onTap composition (Task 13), the navigator-key vs initState choice for the env var (Task 13), and real component constructor signatures for the zoo (Task 12). Each says "read the file first," not "guess."
