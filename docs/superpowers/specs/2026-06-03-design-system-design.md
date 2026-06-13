# Design System — Design Spec

**Date:** 2026-06-03
**Status:** Approved (brainstorm), pending implementation plan
**Version target:** `0.15.0-alpha` (a `feat:` MINOR bump from `0.14.0-alpha` — PR #76 already shipped 0.14.0-alpha)

## Goal

Make the visual language a real, enforced system so the app stays **consistent as it grows**.

Color is already a real token system: `MeowColors` (a `ThemeExtension`) with three presets — Cozy, Cinema Noir, Glass Aurora (Phase 5). Everything else — text sizes, spacing, corner radius, motion, icon/glyph sizes, opacity, shadow — is still hand-typed inline across ~17 UI files. This spec closes that gap.

### Why now / the problem in numbers

Counts of hand-typed values found in `lib/ui/**`:

| Family | Hand-typed spots | Distinct values today |
|---|---|---|
| Spacing (`EdgeInsets`, `SizedBox`) | ~104 | many |
| Typography (`fontSize:`) | 53 | 12 (9,10,11,12,13,14,15,17,18,20,30,34) |
| Opacity (`withValues(alpha:)`) | 37 | many |
| Radius (`BorderRadius.circular`) | 32 | 9 (3,4,8,10,12,14,16,20,24) |
| Icon/glyph (`size:`) | 32 | several |
| Motion (`Duration` + `Curves`) | ~20 | curves already near-consistent |
| Shadow (`BoxShadow`) | 3 | 3 |

The text sizes pile up at 11/12/13/14 — four sizes within 3px doing nearly the same job. That clustering is the inconsistency a scale removes.

## Decisions (locked during brainstorm)

1. **Deliverable:** tokens **in code** + an **in-app gallery** screen (not doc-only).
2. **Philosophy:** **rationalize** to clean scales, not faithful 1:1 capture. Today's strays snap to the nearest scale step; every change is small (text ≤2px, radius ≤2px, spacing ≤3px) and **reviewed in the gallery before it ships**.
3. **Families:** **all seven** — spacing, typography, radius, motion, icon/glyph, opacity, shadow.
4. **Architecture:** **plain constants per family** (Option 1), not ThemeExtensions. Structural tokens are global (identical across all 3 themes); only the text-style seam touches the theme.
5. **Gallery access:** **hidden in release** (Option B) — ships in every build, no visible entry point; opens via **long-pressing the version badge**, plus `MEOWWATCH_GALLERY=1` env var as a backup door. *(The brainstorm chose "tap 5×"; planning found the badge already opens the update dialog on single tap — a modal that would block taps 2–5 — so long-press was substituted and confirmed by the user.)*

## Why plain constants, not ThemeExtensions

`MeowColors` earns its `ThemeExtension` machinery (copy/lerp/equals) because colors genuinely vary per theme and cross-fade on theme swap. Spacing, type sizes, radius, motion, icons, opacity, and shadow geometry are **global** — the same in Cozy, Noir, and Aurora — so wrapping them in ThemeExtensions would add per-family boilerplate for values that never change, and animating spacing/radius on a theme swap is pointless motion. Plain `static const` classes are smaller, tree-shakeable, and unit-testable with no widget pump.

The **one** place global meets per-theme is text: a text style's *size and weight* are global, but its *color and font family* come from the active theme (`MeowColors.textPrimary`/`textDim`, and the per-theme `titleFontFamily`, e.g. Noir's serif). A small `context.meowText` helper composes the two. Shadow geometry is global but its color derives from the theme's `scrim`, so shadow tokens take a scrim argument.

## The scales

### Typography — 6 named roles

Text gets a **role**, not a pixel size. The role owns size + weight.

| Role | Size | Use |
|---|---|---|
| `caption` | 11 | timestamps, sender names, tiny labels |
| `body` | 13 | chat messages, everyday reading text |
| `label` | 15 | buttons, menu rows, field labels |
| `title` | 18 | dialog titles, empty-state headline |
| `heading` | 24 | section headers (new role — room to grow; unused today) |
| `display` | 30 | the "MeowWatch" wordmark / connect title |

Weights: regular + semibold (confirm the exact `FontWeight` set during implementation by reading current usage; the scale defines the two used).

**Changes (all ≤2px), today → role:**
- `9 → 11` (+2), `10 → 11` (+1) → `caption`
- `12 → 13` (+1, ~13 spots), `13 → 13` (—) → `body`
- `14 → 15` (+1, ~12 spots) → `label`, except text whose semantic role is body (chat message → `body` 13, see below); `15 → 15` (—) → `label`
- `17 → 18` (+1), `18 → 18` (—) → `title`
- `30 → 30` (—) → `display`
- Unchanged: 11, 13, 15, 18, 30.

The per-spot counts above are the default numeric snap; the exact role each widget gets is assigned during migration and reviewed in the gallery, so a few 14px spots resolve to `body` 13 rather than `label` 15.

Roles win over raw pixel-snapping: a chat **message body** lands on `body` 13 even though it is 14 today (−1), because its semantic role is body text. Net effect: most small UI text ends up a hair larger. This is the rationalization working; every change is visible in the gallery, theme by theme, before shipping. The **anchored fallback ramp** (11·12·14·18·24·30, text barely moves, tighter gaps) was offered and **declined** in favor of the clean ramp above.

Emoji bursts (20px reaction, 34px floating) are **glyphs, not text** — they live in icon/glyph sizes, unchanged.

### Radius — 6-step ladder

`xs 4 · sm 8 · md 12 · lg 16 · xl 20 · pill 24` (even 4px steps).

**Changes (all ≤2px):** `3 → 4` (+1), `10 → 12` (+2), `14 → 16` (+2). Unchanged: 8, 12, 16, 20, 24.

### Spacing — 8 steps on a 4-grid

`2 · 4 · 8 · 12 · 16 · 20 · 24 · 32`.

The ~104 hand-typed insets/gaps snap to the nearest step; oddballs (e.g. 18, 28) shift ≤3px. Per-spot changes are reviewed in the gallery rather than enumerated here.

### Motion — speeds + easing

- `fast` 120ms — taps, toggles
- `base` 200ms — most transitions
- `slow` 320ms — card glide, dock animations
- `standard` = `Curves.easeOutCubic` (the dominant enter curve today)
- `symmetric` = `Curves.easeInOut`

Today's curves (`easeOut`, `easeOutCubic`, `easeIn`, `easeInOut`) consolidate to these two. Durations snap to the nearest named speed.

**Transient toasts / hints** (e.g. the load-screen "Press Tab to show or hide chat" nudge) must animate **both ways** — never a hard cut. The pattern: fade + slide **in** (slide up a short distance) over `base` with `standard`, hold briefly (~3s), then fade + slide **out** over `base` with `standard`, and only then leave the tree. The exit animation is required, not optional — a hint that vanishes instantly reads as a glitch. Implemented by `_FadingToast` in `lib/ui/home_screen.dart`.

### Icon / glyph sizes

- Icons: `sm 16 · md 20 · lg 24 · xl 32`
- Glyphs (emoji, kept separate from icons): `react 20 · burst 34` (unchanged)

### Opacity levels

`dim 0.60 · scrim 0.50 · disabled 0.38 · pressed 0.12 · hover 0.08`.

These cover the bare `withValues(alpha:)` calls. Some overlap with `MeowColors` (which already bakes alpha into, e.g., `textDim` 0x99 ≈ 0.60); the named levels are for the standalone alpha applications, and `dim` is kept numerically consistent with `textDim`.

### Shadow — 2 tokens

- `card` — `BoxShadow(blur 16, offset (0,4))`
- `overlay` — `BoxShadow(blur 24, offset (0,8))`

Color derives from the active theme's `scrim` at an appropriate alpha, so shadows read correctly on every theme.

## File layout

Mirrors how `MeowColors` already lives under `lib/core/theme/`. Many small, focused files (one family each), per the project's file-organization convention.

```
lib/core/theme/
  meow_theme.dart        (unchanged — MeowColors + presets)
  meow_context.dart      (unchanged — context.meow)
  meow_text.dart         NEW — context.meowText.{caption,body,label,title,heading,display}
  tokens/
    type_scale.dart      NEW — TypeScale sizes + weights (no color)
    spacing.dart         NEW — Spacing.{xxs2,xs4,sm8,md12,lg16,xl20,xxl24,xxxl32} (final names TBD in plan)
    radii.dart           NEW — Radii.{xs,sm,md,lg,xl,pill}
    motion.dart          NEW — Motion.{fast,base,slow,standard,symmetric}
    icon_sizes.dart      NEW — IconSizes.{sm,md,lg,xl}; Glyphs.{react,burst}
    opacities.dart       NEW — Opacities.{dim,scrim,disabled,pressed,hover}
    shadows.dart         NEW — Shadows.card(scrim), Shadows.overlay(scrim)
lib/ui/gallery/
    design_gallery.dart  NEW — the scrollable gallery screen + theme switcher
    sections/            NEW — one small widget per family panel + the component zoo
```

`context.meowText` reads `TypeScale` (size/weight) + `context.meow` (color/`titleFontFamily`) and returns a `TextStyle`. It is the only token accessor that needs `BuildContext`; the rest are plain static references (`Spacing.md`, `Radii.card`, …).

## The gallery

One scrollable screen. A top bar switches Cozy / Cinema Noir / Glass Aurora live (drives the same `themeDataFor(id)` the app already uses), so a token change ripples visibly across all three.

**Sections:**
1. The seven scales, each rendered as a labeled specimen strip (like the brainstorm panels: type ramp, radius ladder, spacing bars, motion list, icon/glyph row, opacity swatches, shadow cards).
2. A **component zoo** — the real widgets shown live so a token edit's effect is obvious: chat bubble, peek tab, connect profile card, player gear menu, update dialog, friend-join banner, reaction bar, empty state.

**Access:** ships in every build (release included) but has **no visible entry point**. Opens via **long-pressing the version badge** (single tap keeps its existing job — opening the update dialog); `MEOWWATCH_GALLERY=1` env var is a backup door (consistent with the existing `MEOWWATCH_FORCE_SW_DECODE` convention). The gallery route is otherwise unreachable in normal use.

## Rollout

Incremental, on a feature branch, small verified commits:

1. **Tokens + `meowText` + unit tests.** Land all seven token files and the text helper with pure headless tests. **Zero UI change** at this step — nothing references the tokens yet.
2. **Gallery.** Build the gallery screen (scales + component zoo + theme switcher + the version-badge gesture). Now changes can be eyeballed before any migration.
3. **Migrate the ~17 UI files**, family by family, to the tokens. Each step: `flutter analyze` stays clean; regenerate affected **goldens** and **visually inspect each PNG** before committing (per CLAUDE.md gotcha); the `chat_overlay_repaint_test` regression guard stays green.
4. **Manual two-instance Release check.** This is a visible change, so a manual pass is warranted before tagging. Verify the Release artifact (`build/windows/x64/runner/Release/...`), kill running instances before building.

## Testing

- **Unit (pure, headless):** each scale asserts its shape — ascending order, no duplicate steps, expected count. The `meowText` composition is tested (size/weight from scale, color/family from theme) since it is the one bit of real logic.
- **Golden:** the ≤2px shifts surface as golden diffs; each affected golden is regenerated with `--update-goldens` and visually inspected. The white-flash regression guard (`chat_overlay_repaint_test`) must stay green.
- **Existing suite** stays green throughout.

## Versioning

`feat:` → MINOR bump: **0.14.0-alpha → 0.15.0-alpha**, in lockstep across `pubspec.yaml` (`version:`), `lib/core/app_version.dart` (`appVersion`), and `CHANGELOG.md` (new top `## [0.15.0-alpha] - 2026-06-03` entry). Keep the `-alpha` suffix.

## Risks / known traps

- **Goldens will churn.** Expected — every affected golden is regenerated and eyeballed, not blind-accepted.
- **The `meowText` seam** (global size/weight + per-theme color/font) is the only real logic; it gets its own test.
- **Release-only white-flash (#50)** is untouched by token work, but the migration alters chat-overlay widgets — keep the `chat_overlay_repaint_test` guard and do the manual Release check.
- **Naming bikeshed.** Final token member names (e.g. spacing step names) are settled in the implementation plan; the values above are fixed.

## Out of scope

- Changing the color tokens or the three theme presets (already a working system).
- New themes, runtime user-editable tokens, or a shipped user-facing design page.
- Elevation beyond the two shadow tokens.
- Restructuring widgets beyond swapping literals for tokens (no behavioral refactor).
