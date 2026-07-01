# Motion Showcase + Docs Finalize (Phase 4) — Implementation Plan

> **For agentic workers:** TDD (RED → GREEN → REFACTOR), one bite-sized step at a
> time, conventional commits, Puro Flutter at
> `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`.

**Goal:** Finish the motion design system's *showcase* — make every shipped
motion token and primitive visible and replayable in the hidden design gallery,
add a gallery-only reduce-motion preview, and finalize the `AGENT_GUIDE` motion
note. This is the last phase of the motion design spec.

**Architecture:** Pure additions to the existing gallery
(`lib/ui/gallery/gallery_sections.dart` + `design_gallery.dart`). No app-runtime
behavior changes — the gallery is reachable only via the version-badge
long-press or `MEOWWATCH_GALLERY=1`. New gallery-internal demo widgets read the
real `Motion.*` tokens and the real primitives so the showcase can never drift
from what ships.

**Tech Stack:** Flutter, existing `Motion` tokens, `ReduceMotionScope`,
`PressableScale`, `RevealIn`, `MotionRacer` pattern.

## Global Constraints

- Version bumps in lockstep across `pubspec.yaml`, `lib/core/app_version.dart`,
  `CHANGELOG.md` — target `0.39.0-alpha` (release-worthiness confirmed with the
  user at the early-inspect checkpoint; a hidden-gallery + docs phase may merge
  without a tag).
- Honor reduce motion via `context.reduceMotion`. App-surface demos degrade;
  raw token *measuring instruments* (the duration/easing racers) keep looping so
  the curve stays legible.
- Gallery loops forever → tests `pump` fixed durations, never `pumpAndSettle`.
- Keep `-alpha`.

---

### Task 1: Motion principles gallery section

**Files:**
- Modify: `lib/ui/gallery/gallery_sections.dart` (new `MotionPrinciplesSpecimen`
  + `_CurveLoop` + `_StagingLoop`; register a `GallerySection` titled
  `Motion · principles`).
- Test: `test/ui/gallery/motion_specimen_test.dart` (extend).

**Design:** Four live specimens, each a labelled tile (title + one-line blurb +
animated area), in the same spirit as `_MotionRacer`:
- **Anticipation** — `Motion.anticipate`: an element slides forward after a tiny
  backward wind-up. Blurb: "A tiny wind-up before the move."
- **Overshoot** — `Motion.springy`: an element rises and settles just past its
  mark, then back. Blurb: "Follow-through that settles past the mark."
- **Squash & stretch** — `Motion.elasticPop`: a 🐾 pops with the reaction-burst
  curve. Blurb: "The one playful beat — the paw-reaction pop."
- **Staging** — one focal motion at a time: a highlight travels across three
  cards, only one raised at any moment. Blurb: "One focal motion at a time."

`_CurveLoop({curve, duration, builder})` repeats `reverse: true`, exposes a
curved `t`, and under `context.reduceMotion` holds the settled end-state (no
loop) — directly demonstrating that reduce motion drops the character.

**Steps (TDD):**
- [ ] Write widget test: pumps `MotionPrinciplesSpecimen`, asserts the four
  titles render (`ANTICIPATION`, `OVERSHOOT`, `SQUASH`, `STAGING` or their cased
  labels) and that pumping fixed durations throws nothing.
- [ ] Write test: under `ReduceMotionScope(reduceMotion: true)` the specimen
  still renders and is static (no exception; a representative frame present).
- [ ] Run → RED.
- [ ] Implement `_CurveLoop`, `_StagingLoop`, `MotionPrinciplesSpecimen`.
- [ ] Register the `Motion · principles` section in `gallerySections()` (after
  `Motion`, before `Motion · list reflow`).
- [ ] Run → GREEN. Commit `feat: add Motion principles gallery section`.

### Task 2: Complete token coverage in the Motion section

**Files:**
- Modify: `lib/ui/gallery/gallery_sections.dart` (`MotionSpecimen`).
- Test: `test/ui/gallery/motion_specimen_test.dart`.

**Design:** Race the monotonic easings only (overshoot/wind-up curves live in
the principles section): add `emphasized` + `emphasizedAccelerate` racers
(keep `standard`, `symmetric`). Add `xfast` + `expressive` duration racers
(keep `fast`/`base`/`slow`). Complete the chip list so every current token is
named: durations `xfast/fast/base/slow/expressive/stagger/reveal`; easings
`standard/symmetric/emphasized/emphasizedAccelerate/springy/elasticPop/
anticipate`.

**Steps (TDD):**
- [ ] Extend test: assert `xfast · 80ms` and `expressive · 440ms` chips exist,
  `emphasized` easing row renders, and `elasticPop` + `anticipate` chips exist.
- [ ] Run → RED.
- [ ] Add the racers + chips.
- [ ] Run → GREEN. Commit `feat: cover every motion token in the gallery`.

### Task 3: PressableScale live demo

**Files:**
- Modify: `lib/ui/gallery/gallery_sections.dart` (`MotionPressableSpecimen` +
  `Motion · pressable` section).
- Test: `test/ui/gallery/motion_specimen_test.dart`.

**Design:** A section with a `PressableScale`-wrapped filled button and an icon,
plus a one-line caption ("Press for the ~3% squash; hover for the lift. Instant
under reduce motion."). Drives the real `PressableScale`.

**Steps (TDD):**
- [ ] Write test: the specimen renders a `PressableScale`; a tap fires its
  callback; under reduce motion it still renders and taps.
- [ ] Run → RED.
- [ ] Implement + register section (after `Motion · reveal`).
- [ ] Run → GREEN. Commit `feat: add PressableScale gallery demo`.

### Task 4: Reduce-motion preview toggle

**Files:**
- Modify: `lib/ui/gallery/design_gallery.dart` (`_DesignGalleryState`,
  `_TopBar`).
- Test: `test/ui/gallery/design_gallery_test.dart`.

**Design:** `_DesignGalleryState` gains `bool _reduceMotion`. Wrap the whole
body in `ReduceMotionScope(reduceMotion: _reduceMotion)` above the
`AnimatedTheme` (via a `Builder` so the melt + every section read it). Add a
`Reduce motion` toggle pill to `_TopBar` next to the theme pills.

**Steps (TDD):**
- [ ] Write test: tapping the `Reduce motion` toggle does not throw and flips a
  visible selected state; gallery still renders its hero.
- [ ] Run → RED.
- [ ] Implement the scope wrap + toggle pill.
- [ ] Run → GREEN. Commit `feat: add a reduce-motion preview toggle to the gallery`.

### Task 5: AGENT_GUIDE note + version bump

**Files:**
- Modify: `docs/AGENT_GUIDE.md` (Motion section — append a short "Showcase"
  paragraph: the gallery is the living motion showcase; new tokens get a chip +
  a racer or principle specimen; the reduce-motion toggle previews the degraded
  form).
- Modify: `pubspec.yaml`, `lib/core/app_version.dart`, `CHANGELOG.md`
  (→ `0.39.0-alpha`).

**Steps:**
- [ ] Append the Motion showcase note.
- [ ] Bump the three version files in lockstep; add the `0.39.0-alpha`
  changelog entry.
- [ ] `flutter analyze` clean + full `flutter test` green.
- [ ] Commit `docs: finalize motion showcase note + bump 0.39.0-alpha`.

---

## Self-Review

- **Spec coverage (Section D):** principles section (T1), new-token specimens
  (T2), PressableScale + RevealIn demos (T3 + existing), launch-reveal replay
  (existing), reduce-motion preview toggle (T4), AGENT_GUIDE note (T5). ✓
- **No app-runtime behavior change** — all additions are gallery-only; the
  release-worthiness of a hidden-gallery phase is a checkpoint question.
- **Naming:** `MotionPrinciplesSpecimen`, `MotionPressableSpecimen`,
  `_CurveLoop`, `_StagingLoop` — match the existing `*Specimen` / `_Motion*`
  convention.
