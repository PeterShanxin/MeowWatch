# MeowWatch Phase 5 — Themes (Design Spec)

**Date:** 2026-05-29
**Status:** Approved (design); ready for implementation plan.
**Phase:** 5 of 6 (see `docs/ROADMAP.md`).

## Goal

Replace the ~57 hardcoded "Cozy" color constants scattered across 13 widget files with a single swappable theme abstraction, ship three presets (**Cozy** default, **Cinema Noir**, **Glass Aurora**), let the user switch theme from both the Connect screen and while watching, and remember the choice across launches.

## Why

Right now every widget hardcodes the Cozy palette inline (`0xFFD4A574`, etc.). There is no way to restyle the app and no single source of truth for color. Phase 5 introduces real theming so MeowWatch can have distinct moods, set up per the master design spec §7.

## Decisions (locked with user)

- **Three presets:** Cozy is the default; Cinema Noir and Glass Aurora are switchable presets.
- **Switcher lives in two places:** theme swatches on the Connect screen *and* a small theme toggle while watching (in the control bar). Switching applies live.
- **Persistence:** the chosen theme is remembered across launches, stored in the existing drift SQLite DB via a new `Settings` key/value table.
- **Architecture:** Flutter `ThemeExtension<MeowColors>` attached to Material `ThemeData`; switching `MaterialApp.theme` animates the transition for free.

## Out of scope (v1 of Phase 5)

- Window-position persistence and hotkey settings (master spec §11 lists them for the same `Settings` table — table is built to hold them, but no UI/wiring this phase).
- Per-profile `theme_override` (master spec §11 nice-to-have).
- Custom user-defined palettes / a color picker.
- A full settings *panel* — the only settings UI this phase is the theme switcher itself.

## Architecture

### Approach chosen: `ThemeExtension`

Pack all MeowWatch-specific colors into a `ThemeExtension<MeowColors>` carried on Material `ThemeData`. The app builds one `ThemeData` per preset and swaps `MaterialApp.theme`; Flutter animates the cross-fade. A thin `context.meow` getter avoids the verbose `Theme.of(context).extension<MeowColors>()!` at every call site.

Alternatives rejected:
- **Custom InheritedWidget** — full control but everything hand-rolled and no free transition animation.
- **provider/ValueNotifier global** — adds a dependency and bypasses Flutter's built-in theme switching.

### The `MeowColors` extension

`MeowColors` is an `@immutable` `ThemeExtension<MeowColors>` with `copyWith` and `lerp` (lerp enables the animated theme transition). Fields cover every semantic slot the current hardcoded constants map to, plus three non-color fields the presets require:

Color slots:
- `background` — base window fill (flat color; used when `backgroundGradient` is null).
- `surface` — chat card / control bar fill.
- `accent` — primary accent (play glyph, scrubber fill, active states).
- `textPrimary` — main text.
- `textDim` — secondary/timestamp text.
- `border` — hairline borders on card / bar.
- `myBubble` — own chat bubble fill.
- `peerBubble` — friend chat bubble fill.

Non-color fields:
- `backgroundGradient` (`Gradient?`, null = use flat `background`) — Aurora's violet→cyan.
- `glassBlur` (`double`, 0 = no blur) — Aurora's frosted glass on card + bar (drives a `BackdropFilter`).
- `titleFontFamily` (`String?`, null = default sans) — Noir's serif. Whether italic is part of the `TextStyle` the widget builds from this family.

> If, during refactor, a hardcoded color does not map cleanly onto one of the slots above, add a new named slot to `MeowColors` rather than reintroducing a literal. The end state is **zero** hardcoded ARGB literals in the 13 widget files.

### The three presets

Defined as `const` (or near-const; gradients aren't const) `MeowColors` instances.

**Cozy** (default — exact current values, so the app looks identical after refactor):

| slot | value |
|---|---|
| background | `0xFF1A1410` |
| surface | `0xF2241B14` |
| accent | `0xFFD4A574` |
| textPrimary | `0xFFF5E6D3` |
| textDim | `0x99F5E6D3` |
| border | `0x55D4A574` |
| myBubble | amber ~22% (`0x38D4A574`) |
| peerBubble | cream ~10% (`0x1AF5E6D3`) |
| backgroundGradient | null |
| glassBlur | 0 |
| titleFontFamily | null |

**Cinema Noir:**

| slot | value |
|---|---|
| background | `0xFF000000` |
| surface | `0xF50C0C0C` |
| accent | `0xFFD4AF37` (gold) |
| textPrimary | `0xFFECECEC` |
| textDim | `0x99ECECEC` |
| border | `0x38D4AF37` (gold ~22%) |
| myBubble | gold ~16% (`0x29D4AF37`) |
| peerBubble | white ~6% (`0x0FFFFFFF`) |
| backgroundGradient | null |
| glassBlur | 0 |
| titleFontFamily | a serif (e.g. bundled Georgia-like / Playfair Display); chat header + titles render serif italic |

**Glass Aurora:**

| slot | value |
|---|---|
| background | `0xFF1E2A4A` (fallback flat, behind gradient) |
| backgroundGradient | linear violet→cyan, e.g. `#2A1B4D → #1E3A5F → #0E3A4A` (140°) |
| surface | white ~10% (`0x1AFFFFFF`) |
| accent | cyan `0xFF7DF9C2` (scrubber may use a cyan→violet gradient; accent solid is the cyan) |
| textPrimary | `0xFFF0F4FF` |
| textDim | `0xA6F0F4FF` |
| border | white ~22% (`0x38FFFFFF`) |
| myBubble | violet ~28% (`0x47A78BFA`) |
| peerBubble | white ~10% (`0x1AFFFFFF`) |
| glassBlur | ~12 (card), bar a bit less — single value, widgets pick sigma |
| titleFontFamily | null |

> Final hex values for Noir/Aurora may be nudged during implementation to match the approved mockups (`.superpowers/brainstorm/.../theme-presets.html`); the table is the starting point, not a contract.

### `MeowThemeId`

`enum MeowThemeId { cozy, noir, aurora }` with a `label` and a mapping to its `MeowColors` preset and built `ThemeData`. Used as the persisted key (store `.name`) and the switcher's selection value.

## Persistence

### `Settings` table (drift)

Add a key/value table to the existing `AppDatabase`:

```
Settings:
  key   TEXT primary key
  value TEXT
```

- Bump `schemaVersion` 1 → 2 and add a `MigrationStrategy` with `onUpgrade` that creates the `Settings` table when upgrading from v1 (existing users keep their profiles + history). `onCreate` creates all tables as usual for fresh installs.
- Regenerate drift codegen (`app_database.g.dart`).

### `SettingsStore`

Follow the existing repository pattern (`lib/core/data/stores.dart` holds the abstract interfaces; drift impls alongside):

- Abstract `SettingsStore`:
  - `Future<String?> get(String key)`
  - `Future<void> set(String key, String value)`
  - (optionally) `Stream<String?> watch(String key)` for live updates — only if needed.
- `DriftSettingsStore` implements it against the `Settings` table (upsert on set).
- Theme key constant, e.g. `kThemeSettingKey = 'theme'`; value = `MeowThemeId.name`.

## UI wiring

### App root (`app.dart`)

- On startup, read the saved theme id from `SettingsStore` (default `cozy` if absent/unknown), hold it as app state (StatefulWidget or a small `ValueNotifier` at root).
- Build a `ThemeData` per `MeowThemeId` (each carrying its `MeowColors` extension; keep the existing `ColorScheme.fromSeed` seeded from that preset's accent so Material widgets stay coherent).
- Pass the active `ThemeData` to `MaterialApp.theme`. Provide a callback down the tree (`onThemeChanged(MeowThemeId)`) that updates state *and* persists via `SettingsStore.set`.

### Connect screen switcher

- Three small theme swatches (mini color chips, like the mockup labels) on the Connect/lobby screen.
- Tapping one calls `onThemeChanged` → live re-theme + persist. The current theme chip is marked selected.

### In-watch switcher

- A small theme button in the auto-hiding control bar (cycle or popup of the three). Applies live so the user sees it over real video.
- Reuses the same `onThemeChanged` path.

### Refactor the 13 widget files

Replace every hardcoded constant with `context.meow.<slot>`. Widgets that need the non-color fields:
- Background: render `backgroundGradient` if non-null, else flat `background`.
- Chat card + control bar: wrap in `BackdropFilter` when `glassBlur > 0`.
- Chat header / titles: build `TextStyle` with `titleFontFamily` (serif italic for Noir) when non-null.

## Testing (TDD)

- **`MeowColors` unit tests:** each preset exposes expected values; `lerp` interpolates between two presets (midpoint sanity); `copyWith` overrides one slot.
- **`SettingsStore` tests:** round-trip set/get on an in-memory DB; missing key → null; overwrite.
- **Migration test:** open a v1 in-memory DB, run migration to v2, assert `Settings` table usable and existing profiles/history survive.
- **Switcher widget tests:** tapping a Connect-screen swatch fires `onThemeChanged` with the right id; control-bar toggle fires it too.
- **Golden updates:** chat widgets have goldens; regenerate per affected theme with `--update-goldens` and eyeball the PNGs before committing (per CLAUDE.md).
- Keep `flutter analyze` at "No issues found!" and the full suite green.

## Manual verification (gate for tagging Phase 5 complete)

Per CLAUDE.md, do not tag the phase complete until the user confirms a manual test in the Release build:
1. Launch, default theme is Cozy and looks identical to today.
2. Switch to Noir on Connect screen → black/gold/serif applies; enter a room, switch to Aurora in control bar → gradient + frosted glass applies live.
3. Close and relaunch → last chosen theme is restored.

## Files

- **New** `lib/core/theme/meow_theme.dart` — `MeowColors` ThemeExtension, `MeowThemeId`, three presets, `themeDataFor(id)`.
- **New** `lib/core/theme/meow_context.dart` — `context.meow` getter extension.
- **New** `lib/core/data/settings_store.dart` (or add to `stores.dart`) — abstract `SettingsStore` + `DriftSettingsStore`.
- **Modify** `lib/core/data/app_database.dart` — add `Settings` table, bump schemaVersion to 2, add `MigrationStrategy`; regenerate `.g.dart`.
- **Modify** `lib/app.dart` — hold active theme id, build per-theme `ThemeData`, swap `MaterialApp.theme`, persist on change.
- **Modify** `lib/main.dart` — load saved theme before first frame; pass `SettingsStore`.
- **Modify** Connect screen — theme swatches.
- **Modify** control bar widget — in-watch theme toggle.
- **Modify** the ~13 widget files currently holding hardcoded Cozy constants — swap to `context.meow.*`.
- **Modify** chat goldens — regenerate.
