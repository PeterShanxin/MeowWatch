# Phase 3 — In-room + controls motion Implementation Plan

> **For agentic workers:** TDD task-by-task. Steps use checkbox (`- [ ]`) syntax. Run the
> Puro Flutter binary: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`.

**Goal:** Bring the in-room surfaces and everyday controls onto the motion system — banners
slide+fade+settle, reaction bursts get the one elastic pop+arc, the mascot quiets when video
plays, the playback bar auto-hides with a hint of anticipation, and every pressable shares one
`PressableScale` press/hover feel — all instant under reduce motion.

**Architecture:** Most surfaces already exist as widgets with ad-hoc durations and plain
`AnimatedOpacity`. This phase adds two foundation tokens (`xfast`, `elasticPop`) and one new
primitive (`PressableScale`), then threads tokens + the spec's specific motions through the
existing widgets. No new heavy deps. Reduce motion (`context.reduceMotion`) degrades every new
motion to an instant present.

**Tech Stack:** Flutter (Puro stable), existing `Motion.*` tokens, `RevealIn`-style primitives.

## Global Constraints

- Draw timing/easing only from `Motion.*` (`lib/core/theme/tokens/motion.dart`) — never ad-hoc `Duration`s.
- Every new motion checks `context.reduceMotion` and degrades to instant (no overshoot, duration→0).
- Version bumps in lockstep: `pubspec.yaml`, `lib/core/app_version.dart`, `CHANGELOG.md` → **0.38.0-alpha**.
- Conventional commits; small commit per task.
- Source of truth: `docs/superpowers/specs/2026-06-25-motion-and-launch-reveal-design.md` §C (In-room),
  §"Everyday controls", §A (tokens). Gallery/docs finalize is **Phase 4**, NOT this PR.
- Never touch `home_screen.dart` teardown/dispose paths — issue #176 is actively editing them.
  Tasks 6–8 below touch `home_screen.dart`/`video_surface.dart` *render* code only; do them last so a
  rebase against the #176 fix stays cheap.

---

### Task 1: Foundation tokens — `xfast` + `elasticPop`

**Files:**
- Modify: `lib/core/theme/tokens/motion.dart`
- Test: `test/core/theme/tokens/motion_test.dart`

**Produces:** `Motion.xfast` (`Duration(milliseconds: 80)`) — press/hover feedback.
`Motion.elasticPop` (`Cubic` overshoot stronger than `springy`, e.g. `Cubic(0.2, 1.5, 0.4, 1.0)`) —
the *one* squash-&-stretch beat (reaction bursts). All other tokens already exist.

- [ ] Step 1: Add a test asserting `Motion.xfast == Duration(milliseconds: 80)` and that
  `Motion.elasticPop` exists and overshoots (`transform(0.6) > 1.0`). Run it → FAIL.
- [ ] Step 2: Add the two tokens with doc comments (xfast = press/hover; elasticPop = the lone
  squash-&-stretch, scoped to reaction bursts). Run test → PASS.
- [ ] Step 3: Commit `feat: add xfast + elasticPop motion tokens`.

### Task 2: `PressableScale` primitive

**Files:**
- Create: `lib/ui/motion/pressable_scale.dart`
- Test: `test/ui/motion/pressable_scale_test.dart`

**Interfaces — Produces:** `PressableScale({required Widget child, VoidCallback? onPressed,
String? semanticLabel, double pressedScale = 0.97})`. On press-down animates to `pressedScale`
over `Motion.xfast`; releases back; optional subtle hover lift (scale ~1.02) on pointer enter.
Under `context.reduceMotion` it is a plain tap target (no scale, instant). Wraps any child; does
not change layout size.

- [ ] Step 1: Test — pump a `PressableScale`, send a pointer-down, pump `Motion.xfast`, assert the
  child's `Transform` scale ≈ `pressedScale`; release → back to 1.0; tapping fires `onPressed`. Run → FAIL.
- [ ] Step 2: Test — with reduce motion on, press shows no scale change but `onPressed` still fires. Run → FAIL.
- [ ] Step 3: Implement with `GestureDetector`/`MouseRegion` + `AnimatedScale` (or a controller),
  reduce-motion guard. Run both tests → PASS.
- [ ] Step 4: Commit `feat: add PressableScale press/hover primitive`.

### Task 3: Reaction bursts — elastic pop + arc

**Files:**
- Modify: `lib/ui/reactions/floating_reactions.dart` (`_FloatingEmojiState.build` + controller duration)
- Test: `test/ui/reactions/floating_reactions_test.dart`

Current `_FloatingEmoji` rises with a linear pop-in (`t<0.18`) + sine sway. Replace with:
the pop-in scale driven by `Motion.elasticPop` (the squash-&-stretch beat), horizontal travel along
a real **arc** (ease the x-drift across the rise, not a buzzing sine), token-based duration. Keep the
`_laneFractions` no-`Math.random` scatter. Reduce motion: emoji still appears + rises + removes itself,
but no elastic overshoot.

- [ ] Step 1: Test — launch one emoji, pump an early frame, assert scale > 1.0 at the pop peak
  (overshoot) when reduce motion is off; assert no overshoot (scale ≤ 1.0) when on. Run → FAIL.
- [ ] Step 2: Test — assert the glyph removes itself at end (existing onDone) still holds. Run.
- [ ] Step 3: Implement elastic pop + arc + tokens + reduce-motion guard. Run tests → PASS.
- [ ] Step 4: Commit `feat: reaction bursts get an elastic pop and an arc`.

### Task 4: Idle mascot — quiet on play + freeze under reduce motion

**Files:**
- Modify: `lib/ui/idle_mascot.dart`
- Test: `test/ui/idle_mascot_test.dart`

Mascot already breathes/wags/blinks on a 4s repeat. Spec: "stops the instant video plays." Add a
`playing` bool (or `animate`) — when false, hold the controller at a resting frame (stop/reset),
when true repeat. Under `context.reduceMotion`, hold the resting frame (no repeat). The mascot only
shows on the empty screen today, but gate the controller so it never animates needlessly.

- [ ] Step 1: Test — pump with `animate:false` (or reduce motion on), assert the controller is not
  animating (`isAnimating == false`) and paints the rest frame. Run → FAIL.
- [ ] Step 2: Implement the guard (`initState`/`didUpdateWidget` start/stop, reduce-motion check). Run → PASS.
- [ ] Step 3: Commit `feat: idle mascot rests when video plays or reduce motion is on`.

### Task 5: Chat/reaction-bar expand on tokens

**Files:**
- Modify: `lib/ui/reactions/reaction_bar.dart` (the `AnimatedSize` `160ms`/`easeOut` → `Motion.fast`/`Motion.standard`)
- Modify: chat collapse animation if it uses an ad-hoc duration (grep `chat_overlay.dart` for `Duration(`)
- Test: `test/ui/reactions/reaction_bar_test.dart` (assert open/close toggles; smoke that tokens are used)

- [ ] Step 1: Test — tapping `reaction-toggle` opens the emoji row (emoji buttons present), tapping
  again closes it. Run → confirm current behavior, then switch durations to tokens. Run → PASS.
- [ ] Step 2: Unify any ad-hoc chat collapse duration on `Motion.*`. Run chat tests → PASS.
- [ ] Step 3: Commit `refactor: unify reaction/chat expand on motion tokens`.

### Task 6: Friend join/leave banner — slide + fade + springy settle

**Files (touches `home_screen.dart` render only):**
- Modify: `lib/ui/home_screen.dart` — wrap the `_SyncHintBanner` mount (`~:1496`) / the `_SyncHintBanner`
  widget (`~:1678`) so it enters with a slide-down + fade and a gentle `Motion.springy` settle, fades on dismiss.
- Test: `test/ui/home_screen` banner test (or a focused widget test extracting `_SyncHintBanner` into its
  own file `lib/ui/sync_hint_banner.dart` so it is testable in isolation).

**Note:** Prefer extracting `_SyncHintBanner` → `lib/ui/sync_hint_banner.dart` (public widget) so it has a
direct test and the giant `home_screen.dart` shrinks. The banner becomes a small stateful reveal
(`RevealIn`-style) keyed on its text so a new notice re-triggers the entrance.

- [ ] Step 1: Extract `SyncHintBanner` to its own file; update the import in `home_screen.dart`. Run analyze.
- [ ] Step 2: Test — pump `SyncHintBanner(text:'…')`, assert it slides+fades to settled; with reduce
  motion, it's present immediately at full opacity/offset 0. Run → FAIL.
- [ ] Step 3: Implement the entrance (slide+fade, `Motion.base`/`springy`, reduce-motion instant). Run → PASS.
- [ ] Step 4: Commit `feat: friend join/leave banner slides in and settles`.

### Task 7: "Loaded — in sync!" reveal on video load

**Files:**
- Modify: `lib/ui/home_screen.dart` — fire a transient notice via the existing `_showTransientNotice`
  path (`~:919`, `~:486`) when a local video finishes loading into a synced room.
- Test: extend the transient-notice / banner test.

Reuse the existing transient-banner machinery (auto-clears) rather than a new overlay. Message: a brief
"Loaded — in sync!" when the file is loaded and sync is healthy. Honors the same banner motion from Task 6.

- [ ] Step 1: Test — on a load-complete + healthy-sync transition, `_showTransientNotice` is called with
  a "in sync" message (assert via the banner text exposed in the widget tree). Run → FAIL.
- [ ] Step 2: Implement the trigger at the load-complete site. Run → PASS.
- [ ] Step 3: Commit `feat: brief "Loaded — in sync!" confirmation on load`.

### Task 8: Auto-hiding playback bar — slide + fade with anticipation

**Files (touches the video overlay render only):**
- Find + Modify: the `PlaybackBar` mount (grep `PlaybackBar(` — likely `lib/ui/video_surface.dart`),
  where `_isUiIdle`/`overlayOpacity` drives visibility today.
- Test: `test/ui/...` for the bar's show/hide.

Replace the plain opacity hide with a combined `AnimatedSlide` (bar drops down a few px on hide) +
`AnimatedOpacity`, with a hint of anticipation on the *hide* (a tiny upward wind-up before it drops) —
keep show snappy. Tokens: `Motion.base`/`Motion.standard`. Reduce motion: instant show/hide, no slide.

- [ ] Step 1: Test — bar visible when not idle; on idle it animates out (offset + opacity); reduce motion
  → instant. Run → FAIL.
- [ ] Step 2: Implement slide+fade+anticipation, tokens, reduce-motion guard. Run → PASS.
- [ ] Step 3: Commit `feat: playback bar slides away with a hint of anticipation`.

### Task 9: Apply `PressableScale` app-wide

**Files:**
- Modify: `lib/ui/instant_tap_icon.dart`, `lib/ui/volume_control.dart`, primary buttons in
  `connect_screen.dart` / empty-state / menu buttons — wrap their tap targets in `PressableScale`.
- Test: one representative test that a wrapped button still fires `onPressed` and scales on press.

Keep it light: wrap the shared tap primitives (so the feel propagates) rather than every call site.
Verify `InstantTapIcon` keeps its instant-tap semantics (it's named for low-latency taps — `PressableScale`'s
press scale must not delay the callback; fire `onPressed` on tap-down-then-up as today).

- [ ] Step 1: Test — `InstantTapIcon` press scales + still fires immediately. Run → FAIL/adjust.
- [ ] Step 2: Wrap the shared primitives; spot-wrap the connect/empty-state primary buttons. Run suite → PASS.
- [ ] Step 3: Commit `feat: shared PressableScale press feel on buttons`.

### Task 10: Version bump + changelog

**Files:** `pubspec.yaml`, `lib/core/app_version.dart`, `CHANGELOG.md`

- [ ] Step 1: Bump all three to `0.38.0-alpha`; add a user-facing `## [0.38.0-alpha] - 2026-06-29`
  entry with `### Added`/`### Improved` notes (banner slide-in, reaction pop, calmer mascot, auto-hiding
  bar, unified button feel). Run `flutter analyze` + full `flutter test`.
- [ ] Step 2: Commit `chore: bump to 0.38.0-alpha for in-room motion`.

---

## Self-review notes
- Spec coverage: banner (T6), loaded reveal (T7), reaction pop+arc (T3), mascot quiet (T4), seek/sync
  fade — folded into banner/notice motion (T6/T7); playback bar (T8), chat expand (T5), buttons (T9),
  volume/seek popups — `volume_control` wrapped in T9. Gallery/principles = Phase 4 (out of scope).
- Conflict order: T1–T5 + T9 are self-contained widgets; T6–T8 touch `home_screen.dart`/`video_surface.dart`
  render code — done last for a cheap rebase against #176.
- Every task has a reduce-motion assertion where it adds motion.
