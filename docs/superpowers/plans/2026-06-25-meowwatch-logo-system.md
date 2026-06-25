# MeowWatch Logo System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the "Neon Nine" MeowWatch brand mark + wordmark as reusable,
theme-tinted Flutter widgets, and wire them into the lobby header and the design
gallery.

**Architecture:** The mark is a pure `CustomPainter` drawn in a 64×64 space and
tinted to the live theme accent (no SVG, no image asset). The wordmark is a
`Text.rich` in the bundled **Sora** font with a soft accent glow. A `MeowLogo`
lockup composes the two (horizontal or stacked). All colors come from the
existing `MeowColors` theme extension via `context.meow`, so the brand matches
Cozy / Cinema Noir / Glass Aurora automatically.

**Tech Stack:** Flutter (Dart), `flutter_test`, golden tests. New asset: the Sora
font (SIL OFL).

## Global Constraints

- **Flutter binary (NOT on PATH):** `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`. Use it for every `analyze` / `test` / `build`.
- **Keep `flutter analyze` at "No issues found!"** after every task.
- **Versioning (this is a behavior-changing PR):** bump the version in lockstep across `pubspec.yaml` (`version:`), `lib/core/app_version.dart` (`appVersion`), and `CHANGELOG.md`. Target version for this plan: **`0.35.0-alpha`** (minor bump — a new feature; keep `-alpha`). Build number `+1`.
- **Immutability / small files** per repo coding style: new widgets live in their own focused files under `lib/ui/brand/`.
- **No Claude attribution** in commits.
- **Brand colors are never hardcoded in widgets** — read `context.meow.accent` / `.textPrimary`. Literal hexes appear only in the (offline) launcher-icon step.
- Mark coordinates/stroke widths are **verbatim** from the design handoff (Appendix B of `docs/superpowers/specs/2026-06-25-motion-and-launch-reveal-design.md`); do not "tidy" them.

---

### Task 1: `MeowLogoMark` — the cat mark (CustomPainter)

**Files:**
- Create: `lib/ui/brand/meow_logo_mark.dart`
- Test: `test/ui/brand/meow_logo_mark_test.dart`
- Test (golden): `test/ui/brand/goldens/meow_logo_mark_cozy.png` (generated)

**Interfaces:**
- Produces: `class MeowLogoMark extends StatelessWidget` with
  `const MeowLogoMark({Key? key, double size = 40, Color? color})`. When `color`
  is null it uses `context.meow.accent`.

- [ ] **Step 1: Write the failing smoke test**

```dart
// test/ui/brand/meow_logo_mark_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/brand/meow_logo_mark.dart';

void main() {
  testWidgets('MeowLogoMark renders at the given size without error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(body: Center(child: MeowLogoMark(size: 80))),
    ));
    final box = tester.getSize(find.byType(MeowLogoMark));
    expect(box, const Size(80, 80));
  });

  testWidgets('MeowLogoMark uses the theme accent when no color is given',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.aurora),
      home: const Scaffold(body: Center(child: MeowLogoMark(size: 40))),
    ));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/brand/meow_logo_mark_test.dart`
Expected: FAIL — `meow_logo_mark.dart` / `MeowLogoMark` not found.

- [ ] **Step 3: Implement the mark**

```dart
// lib/ui/brand/meow_logo_mark.dart
import 'package:flutter/widgets.dart';

import '../../core/theme/meow_context.dart';

/// The MeowWatch "Neon Nine" mark: a rounded-square cat face with cat-eye slits
/// and a nose dot. Drawn in a 64×64 space and tinted to one [color] (defaults to
/// the theme accent). Pure vector — no asset, crisp at any size. Geometry is
/// verbatim from the Neon Nine design handoff.
class MeowLogoMark extends StatelessWidget {
  const MeowLogoMark({super.key, this.size = 40, this.color});

  final double size;

  /// Tint for the whole mark; falls back to the live theme accent.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.meow.accent;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MeowLogoMarkPainter(tint)),
    );
  }
}

class _MeowLogoMarkPainter extends CustomPainter {
  _MeowLogoMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw in the design's native 64×64 space, then scale to the widget size so
    // every coordinate and stroke width below is verbatim from the handoff.
    canvas.save();
    canvas.scale(size.width / 64.0, size.height / 64.0);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    // Ears (stroke 2.6, no fill).
    line.strokeWidth = 2.6;
    canvas.drawPath(
      _triangle(const Offset(19, 17), const Offset(22, 6), const Offset(32, 15)),
      line,
    );
    canvas.drawPath(
      _triangle(const Offset(45, 17), const Offset(42, 6), const Offset(32, 15)),
      line,
    );

    // Head: rounded square (13,15) 38×38, corner radius 14.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 15, 38, 38),
        const Radius.circular(14),
      ),
      line,
    );

    // Cat-eye slits (stroke 3.2).
    line.strokeWidth = 3.2;
    canvas.drawLine(const Offset(25, 30), const Offset(25, 38), line);
    canvas.drawLine(const Offset(39, 30), const Offset(39, 38), line);

    // Nose dot.
    canvas.drawCircle(const Offset(32, 42), 1.7, fill);

    canvas.restore();
  }

  Path _triangle(Offset a, Offset b, Offset c) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..close();

  @override
  bool shouldRepaint(_MeowLogoMarkPainter old) => old.color != color;
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/brand/meow_logo_mark_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Add a golden test to lock the geometry**

Append to `test/ui/brand/meow_logo_mark_test.dart`:

```dart
  testWidgets('MeowLogoMark golden (cozy)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(
        backgroundColor: Color(0xFF1A1410),
        body: Center(child: MeowLogoMark(size: 200)),
      ),
    ));
    await expectLater(
      find.byType(MeowLogoMark),
      matchesGoldenFile('goldens/meow_logo_mark_cozy.png'),
    );
  });
```

- [ ] **Step 6: Generate the golden + verify**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/brand/meow_logo_mark_test.dart --update-goldens`
Then run without the flag to confirm it matches:
`C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/brand/meow_logo_mark_test.dart`
Expected: PASS. A new file `test/ui/brand/goldens/meow_logo_mark_cozy.png` exists.

- [ ] **Step 7: Analyze + commit**

```bash
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
git add lib/ui/brand/meow_logo_mark.dart test/ui/brand/
git commit -m "feat: add MeowLogoMark (Neon Nine cat mark)"
```

---

### Task 2: Bundle the Sora font + `MeowWordmark`

**Files:**
- Create: `assets/fonts/Sora.ttf` (downloaded), `assets/fonts/Sora-OFL.txt` (license)
- Modify: `pubspec.yaml` (add the font under `flutter: fonts:` and ensure `assets/fonts/` is covered)
- Create: `lib/ui/brand/meow_wordmark.dart`
- Test: `test/ui/brand/meow_wordmark_test.dart`

**Interfaces:**
- Produces: `class MeowWordmark extends StatelessWidget` with
  `const MeowWordmark({Key? key, double fontSize = 24, Color? meowColor, Color? watchColor, Color? glowColor})`.
  Defaults: `meowColor = context.meow.textPrimary`, `watchColor = glowColor = context.meow.accent`.

Note on testing: `flutter test` does not rasterize real bundled fonts, so the
wordmark is verified structurally (plain text + per-span colors), **not** with a
golden — a golden would capture the test fallback glyphs, not Sora.

- [ ] **Step 1: Download the Sora variable font + license**

Sora exposes a `wght` axis, so one variable file covers every weight; Flutter
maps `FontWeight.w600` onto that axis.

```bash
mkdir -p assets/fonts
curl -L -o assets/fonts/Sora.ttf "https://github.com/google/fonts/raw/main/ofl/sora/Sora%5Bwght%5D.ttf"
curl -L -o assets/fonts/Sora-OFL.txt "https://github.com/google/fonts/raw/main/ofl/sora/OFL.txt"
```

Verify the font is a real TTF (non-trivial size, starts with the TrueType magic):
`ls -l assets/fonts/Sora.ttf` (expect ~100KB+, not an HTML error page).

- [ ] **Step 2: Register the font in `pubspec.yaml`**

Under the existing `flutter:` section, add a `fonts:` block (sibling of `assets:`)
and add `assets/fonts/` to the asset list:

```yaml
  assets:
    - assets/sounds/
    - assets/fonts/
    - CHANGELOG.md

  fonts:
    - family: Sora
      fonts:
        - asset: assets/fonts/Sora.ttf
```

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat pub get`
Expected: resolves with no error.

- [ ] **Step 3: Write the failing test**

```dart
// test/ui/brand/meow_wordmark_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/brand/meow_wordmark.dart';

void main() {
  testWidgets('MeowWordmark shows the full plain text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(body: Center(child: MeowWordmark())),
    ));
    expect(find.text('MeowWatch'), findsOneWidget);
  });

  testWidgets('MeowWordmark colors Watch with the accent and uses Sora',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.aurora),
      home: const Scaffold(body: Center(child: MeowWordmark())),
    ));
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    final root = rich.text as TextSpan;
    final spans = root.children!.cast<TextSpan>();
    expect(spans[0].text, 'Meow');
    expect(spans[1].text, 'Watch');
    expect(spans[1].style!.color, const Color(0xFF7DF9C2)); // aurora accent
    expect(spans[0].style!.fontFamily, 'Sora');
  });
}
```

- [ ] **Step 4: Run the test, verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/brand/meow_wordmark_test.dart`
Expected: FAIL — `MeowWordmark` not found.

- [ ] **Step 5: Implement the wordmark**

```dart
// lib/ui/brand/meow_wordmark.dart
import 'package:flutter/widgets.dart';

import '../../core/theme/meow_context.dart';

/// The "MeowWatch" wordmark in Sora 600: "Meow" in the light text color,
/// "Watch" in the theme accent, with a soft accent glow. Colors default to the
/// live theme.
class MeowWordmark extends StatelessWidget {
  const MeowWordmark({
    super.key,
    this.fontSize = 24,
    this.meowColor,
    this.watchColor,
    this.glowColor,
  });

  final double fontSize;
  final Color? meowColor;
  final Color? watchColor;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final meow = meowColor ?? c.textPrimary;
    final watch = watchColor ?? c.accent;
    final glow = glowColor ?? c.accent;

    final base = TextStyle(
      fontFamily: 'Sora',
      fontWeight: FontWeight.w600,
      fontSize: fontSize,
      letterSpacing: fontSize * 0.01,
      height: 1,
      shadows: [
        Shadow(
          color: glow.withValues(alpha: 0.5),
          blurRadius: fontSize * 0.58,
        ),
      ],
    );

    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Meow', style: base.copyWith(color: meow)),
        TextSpan(text: 'Watch', style: base.copyWith(color: watch)),
      ]),
    );
  }
}
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/brand/meow_wordmark_test.dart`
Expected: PASS (both tests).

- [ ] **Step 7: Analyze + commit**

```bash
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
git add assets/fonts/ pubspec.yaml lib/ui/brand/meow_wordmark.dart test/ui/brand/meow_wordmark_test.dart
git commit -m "feat: add Sora font + MeowWordmark"
```

---

### Task 3: `MeowLogo` lockup (mark + wordmark)

**Files:**
- Create: `lib/ui/brand/meow_logo.dart`
- Test: `test/ui/brand/meow_logo_test.dart`

**Interfaces:**
- Consumes: `MeowLogoMark` (Task 1), `MeowWordmark` (Task 2).
- Produces: `class MeowLogo extends StatelessWidget` with
  `const MeowLogo({Key? key, double markSize = 40, double fontSize = 24, Axis axis = Axis.horizontal, double gap = 16})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/brand/meow_logo_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/brand/meow_logo.dart';
import 'package:meowwatch/ui/brand/meow_logo_mark.dart';
import 'package:meowwatch/ui/brand/meow_wordmark.dart';

void main() {
  testWidgets('MeowLogo composes the mark and wordmark (horizontal)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(body: Center(child: MeowLogo())),
    ));
    expect(find.byType(MeowLogoMark), findsOneWidget);
    expect(find.byType(MeowWordmark), findsOneWidget);
    expect(find.byType(Row), findsWidgets);
  });

  testWidgets('MeowLogo stacks vertically when axis is vertical',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: const Scaffold(
        body: Center(child: MeowLogo(axis: Axis.vertical)),
      ),
    ));
    expect(find.byType(Column), findsWidgets);
    expect(find.byType(MeowLogoMark), findsOneWidget);
    expect(find.byType(MeowWordmark), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/brand/meow_logo_test.dart`
Expected: FAIL — `MeowLogo` not found.

- [ ] **Step 3: Implement the lockup**

```dart
// lib/ui/brand/meow_logo.dart
import 'package:flutter/widgets.dart';

import 'meow_logo_mark.dart';
import 'meow_wordmark.dart';

/// The MeowWatch lockup: the [MeowLogoMark] beside (or above) the
/// [MeowWordmark]. Both tint to the live theme. Use [axis] for horizontal
/// (default) or stacked.
class MeowLogo extends StatelessWidget {
  const MeowLogo({
    super.key,
    this.markSize = 40,
    this.fontSize = 24,
    this.axis = Axis.horizontal,
    this.gap = 16,
  });

  final double markSize;
  final double fontSize;
  final Axis axis;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final mark = MeowLogoMark(size: markSize);
    final word = MeowWordmark(fontSize: fontSize);
    final children = [mark, SizedBox.square(dimension: gap), word];
    return axis == Axis.horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: children)
        : Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/brand/meow_logo_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
git add lib/ui/brand/meow_logo.dart test/ui/brand/meow_logo_test.dart
git commit -m "feat: add MeowLogo lockup"
```

---

### Task 4: Use the logo in the lobby header

**Files:**
- Modify: `lib/ui/connect/connect_screen.dart` (the `_formColumn()` header, around lines 591-596)
- Test: `test/ui/connect/connect_screen_test.dart` (add a case)

**Interfaces:**
- Consumes: `MeowLogo` (Task 3).

- [ ] **Step 1: Write the failing test**

Add to `test/ui/connect/connect_screen_test.dart` (inside its existing `main()`).
If the file already pumps the connect screen via a helper, reuse it; otherwise
this self-contained case works:

```dart
  testWidgets('lobby header shows the MeowLogo lockup', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(body: Builder(builder: (_) => const SizedBox())),
    ));
    // Replace the above with the suite's real ConnectScreen pump helper, then:
    // expect(find.byType(MeowLogo), findsOneWidget);
  });
```

> Implementer note: open `connect_screen_test.dart`, copy its existing
> ConnectScreen pump setup (it already constructs the screen with its required
> stores), and assert `expect(find.byType(MeowLogo), findsOneWidget);` plus
> `expect(find.text('MeowWatch'), findsOneWidget);`. Add
> `import 'package:meowwatch/ui/brand/meow_logo.dart';`.

- [ ] **Step 2: Run the test, verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/connect/connect_screen_test.dart`
Expected: FAIL on the new `find.byType(MeowLogo)` assertion (still a plain Text).

- [ ] **Step 3: Replace the header Text with the lockup**

In `lib/ui/connect/connect_screen.dart`, add the import:

```dart
import '../brand/meow_logo.dart';
```

Replace the header `Text` block in `_formColumn()`:

```dart
      Text(
        'MeowWatch',
        style: context.meowText.display.copyWith(
          fontWeight: TypeScale.semibold,
        ),
      ),
```

with:

```dart
      const MeowLogo(markSize: 40, fontSize: 30),
```

(Leave the `'Watch together, in sync.'` subtitle and everything below it
unchanged. If `TypeScale` becomes unused after this edit, remove its now-dead
import to keep `analyze` clean.)

- [ ] **Step 4: Run the test, verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/connect/connect_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
git add lib/ui/connect/connect_screen.dart test/ui/connect/connect_screen_test.dart
git commit -m "feat: show the MeowLogo in the lobby header"
```

---

### Task 5: Add a "Brand" specimen to the design gallery

**Files:**
- Modify: `lib/ui/gallery/gallery_sections.dart` (add `BrandSpecimen` + a `GallerySection` entry in `gallerySections()`)
- Test: `test/ui/gallery/design_gallery_test.dart` (add a case; fix any count assertion this addition breaks)

**Interfaces:**
- Consumes: `MeowLogo`, `MeowLogoMark` (Tasks 1, 3).
- Produces: `class BrandSpecimen extends StatelessWidget`.

- [ ] **Step 1: Write the failing test**

Add to `test/ui/gallery/design_gallery_test.dart`:

```dart
  testWidgets('gallery includes the Brand specimen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pumpAndSettle();
    expect(find.text('BRAND'), findsOneWidget);
    expect(find.byType(MeowLogo), findsWidgets);
  });
```

Add imports at the top of the test if missing:
`import 'package:meowwatch/ui/brand/meow_logo.dart';`
`import 'package:meowwatch/ui/gallery/design_gallery.dart';`

- [ ] **Step 2: Run the test, verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/gallery/design_gallery_test.dart`
Expected: FAIL — no `BRAND` section / no `MeowLogo`.

- [ ] **Step 3: Implement `BrandSpecimen` and register the section**

In `lib/ui/gallery/gallery_sections.dart`, add the imports:

```dart
import '../brand/meow_logo.dart';
import '../brand/meow_logo_mark.dart';
```

Add the specimen class (near the other `*Specimen` classes):

```dart
/// The brand mark at three sizes, plus the horizontal and stacked lockups, live
/// over the active theme — so a theme switch retints the logo here too.
class BrandSpecimen extends StatelessWidget {
  const BrandSpecimen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;

    Widget label(String s) => Text(
          s.toUpperCase(),
          style: t.caption.copyWith(
            color: c.textPrimary,
            letterSpacing: 1.5,
            fontWeight: TypeScale.semibold,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Mark'),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: const [
            MeowLogoMark(size: 32),
            SizedBox(width: Spacing.xl),
            MeowLogoMark(size: 48),
            SizedBox(width: Spacing.xl),
            MeowLogoMark(size: 72),
          ],
        ),
        const SizedBox(height: Spacing.xl),
        label('Horizontal lockup'),
        const SizedBox(height: Spacing.md),
        const MeowLogo(markSize: 40, fontSize: 28),
        const SizedBox(height: Spacing.xl),
        label('Stacked'),
        const SizedBox(height: Spacing.md),
        const MeowLogo(markSize: 56, fontSize: 26, axis: Axis.vertical, gap: 12),
      ],
    );
  }
}
```

Then add an entry to the `gallerySections()` list (place it first, right after
the opening `[`, so the brand leads the page):

```dart
      GallerySection(
        title: 'Brand',
        description:
            'The Neon Nine mark + Sora wordmark, tinted live to the active '
            'theme. Mark is pure vector; "Watch" + glow take the accent.',
        child: BrandSpecimen(),
      ),
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/gallery/design_gallery_test.dart`
Expected: PASS. If a pre-existing assertion counted sections, update that count by +1.

- [ ] **Step 5: Run the full gallery + specimen suites**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/gallery/`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

```bash
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze
git add lib/ui/gallery/gallery_sections.dart test/ui/gallery/design_gallery_test.dart
git commit -m "feat: add Brand specimen to the design gallery"
```

---

### Task 6: Version bump + changelog + full green

**Files:**
- Modify: `pubspec.yaml` (`version:`)
- Modify: `lib/core/app_version.dart` (`appVersion`)
- Modify: `CHANGELOG.md` (new top entry)

**Interfaces:** none.

- [ ] **Step 1: Bump `pubspec.yaml`**

Change `version: 0.34.1-alpha+1` to:

```yaml
version: 0.35.0-alpha+1
```

- [ ] **Step 2: Bump `lib/core/app_version.dart`**

Set the `appVersion` constant to `'0.35.0-alpha'` (match the existing string
format in that file exactly).

- [ ] **Step 3: Add the `CHANGELOG.md` entry**

Insert a new entry at the top of the version list (use today's date,
2026-06-25), written for the end user per the repo's changelog style:

```markdown
## [0.35.0-alpha] - 2026-06-25

> MeowWatch has a real logo now.

### Added
- A proper **MeowWatch logo** — a glowing cat mark + wordmark that recolors
  itself to match your theme. It greets you on the lobby screen, and lives in
  the design gallery alongside the other tokens.
```

- [ ] **Step 4: Verify the three versions match**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Confirm by eye that `pubspec.yaml`, `lib/core/app_version.dart`, and the top of
`CHANGELOG.md` all read `0.35.0-alpha`.

- [ ] **Step 5: Run the whole suite**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test`
Expected: PASS (entire suite). Fix any fallout before committing.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml lib/core/app_version.dart CHANGELOG.md
git commit -m "chore: bump to 0.35.0-alpha (logo system)"
```

---

### Task 7 (optional, splittable to its own PR): Windows launcher icon

The in-app brand is done after Task 6; the `.exe` launcher icon is offline
tooling (not TDD-able), so it may ship in this PR or a follow-up.

**Files:**
- Modify: `pubspec.yaml` (add `flutter_launcher_icons` dev dependency + config)
- Create: `assets/brand/app_icon_source.png` (1024×1024 mark on a rounded tile)
- Regenerate: `windows/runner/resources/app_icon.ico`

- [ ] **Step 1: Produce a 1024×1024 source PNG** of the mark centered on a
  rounded-square tile. Use the Aurora tile (Neon Nine is "at home in Aurora"):
  background gradient `#2A1B4D → #1E3A5F → #0E3A4A`, mark in `#7DF9C2`, corner
  radius ≈ 232px (`0.227 × 1024`), mark ≈ 600px (`0.587 × 1024`), centered. Save
  as `assets/brand/app_icon_source.png`. (Generate it however is convenient — a
  one-off Flutter screenshot of `MeowLogoMark` on an Aurora tile, or any image
  tool. It is a build input, not shipped at runtime.)

- [ ] **Step 2: Add `flutter_launcher_icons`** to `dev_dependencies` and a config
  block in `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.1

flutter_launcher_icons:
  windows:
    generate: true
    image_path: assets/brand/app_icon_source.png
    icon_size: 256
```

- [ ] **Step 3: Generate the icon**

Run:
`C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat pub get`
`C:/Users/shanx/.puro/envs/stable/flutter/bin/dart.bat run flutter_launcher_icons`
Expected: `windows/runner/resources/app_icon.ico` is rewritten.

- [ ] **Step 4: Verify in a Release build**

Kill any running build-output `meowwatch.exe` first (a running instance holds a
lock and the build still reports success — see AGENT_GUIDE Gotchas). Then:
`C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat build windows`
Launch `build/windows/x64/runner/Release/meowwatch.exe` and confirm the new
taskbar/window icon.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml assets/brand/ windows/runner/resources/app_icon.ico
git commit -m "feat: regenerate the Windows launcher icon from the new mark"
```

---

## Self-Review

**Spec coverage (against the Neon Nine logo scope of the design spec):**
- Mark as `CustomPainter`, theme-tinted, no asset → Task 1. ✓
- Wordmark in Sora with accent glow → Task 2. ✓
- Lockup (horizontal + stacked) → Task 3. ✓
- Lobby header uses the brand → Task 4. ✓
- Showcase/gallery brand specimen → Task 5. ✓
- Version lockstep + changelog → Task 6. ✓
- Windows launcher icon → Task 7. ✓
- *Out of scope here (next plan):* the launch reveal, motion tokens, reduce-motion
  switch, and the rest of the surfaces — they depend on this brand and are
  sequenced after it per "logo first."

**Placeholder scan:** Task 4 Step 1 intentionally defers to the suite's existing
ConnectScreen pump helper (the implementer copies the real setup rather than
guess the stores' constructors) — this is a directed instruction with the exact
assertions to add, not a vague placeholder. All code steps carry full code.

**Type consistency:** `MeowLogoMark({size, color})`, `MeowWordmark({fontSize,
meowColor, watchColor, glowColor})`, and `MeowLogo({markSize, fontSize, axis,
gap})` are used identically everywhere they appear (Tasks 3-5). Font family
string `'Sora'` matches between the pubspec registration (Task 2 Step 2), the
widget (Task 2 Step 5), and the test (Task 2 Step 3).
