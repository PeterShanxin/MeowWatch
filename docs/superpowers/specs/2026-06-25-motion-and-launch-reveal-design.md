# Motion design system + launch reveal — design

- **Date:** 2026-06-25
- **Status:** Approved (brainstorm); plan to follow
- **Owner:** shanxin

## Summary

MeowWatch already has a real motion foundation — `Motion` tokens
(`fast/base/slow/stagger`, `standard`/`symmetric` easings), a live motion
gallery, and a polished `StaggeredReflowList`. This work *extends* that system
rather than starting over: more, better-felt animation on the surfaces that
benefit, plus a first real brand logo and a cold-start launch reveal.

**North star:** *Motion explains, it does not perform.* Refined and
near-invisible everywhere; one small character beat where it earns a smile;
nothing ever makes the user wait just to watch an animation.

## Locked decisions (from brainstorm)

- **Feel:** refined base + small character moments (not invisible, not
  cartoonish).
- **Priority of surfaces:** first impressions + lobby (highest), then in-room
  moments + everyday controls.
- **Launch concept:** theme gradient *wash* + animated *wordmark*, which
  dissolves as the lobby content *rises in* behind it.
- **Logo:** the app has no real logo today (just the stock Flutter icon). We
  design one first. Pipeline: I provide a logo-design prompt → user picks →
  `pixel2motion` produces a clean layered logo + a browser motion preview to
  approve → the shipped animation is **rebuilt natively** in Flutter.
- **Why native rebuild, not the exported clip:** (1) it follows the user's
  chosen theme palette — a pre-baked clip is frozen in one color set;
  (2) it stays crisp at any window size — raster blurs when scaled;
  (3) it adds ~zero startup cost — no video decode at frame one, which matters
  because this app's most fragile moment is launch.
- **Order of work:** logo + launch reveal first, then everything else.

## Goals

- A single source of truth for all motion (tokens + a few reusable widgets),
  so timing/feel can be tuned globally and stays consistent.
- A cold-start launch reveal: theme wash + wordmark → content rise. Skippable,
  short, cold-start only.
- A real MeowWatch logo (mark + wordmark), vector, theme-tintable.
- Tasteful motion added to the lobby, in-room moments, and everyday controls.
- The Disney "12 principles" subset that maps to UI, codified as named tokens
  and a live showcase section (so the principles are real code, not vibes).
- A **Reduce motion** path honored everywhere (accessibility + the
  stare-at-it-for-hours case).
- The design gallery / showcase updated to document and demo all of it.

## Non-goals

- No bouncy squash-and-stretch across the whole app (kept to the one reaction
  moment).
- No looping/ambient motion while a video is actually playing.
- No animation that blocks first interaction or adds a perceptible wait.
- No new heavy dependencies for playback of pre-rendered motion (no WebView,
  no bundled splash video).

---

## Section A — Motion foundation (design-system layer)

Everything draws from one place: `lib/core/theme/tokens/motion.dart`, extended.

### Timing tokens (add to existing)

| Token | Value | Use |
|-------|-------|-----|
| `xfast` | ~80ms | instant press / hover feedback |
| `fast` | 120ms | *(existing)* small state changes |
| `base` | 200ms | *(existing)* default transition |
| `slow` | 320ms | *(existing)* larger moves |
| `stagger` | 55ms | *(existing)* per-item cascade delay |
| `reveal` | ~800ms | the launch reveal only |

### Easing tokens (add to existing)

| Token | Curve (starting point, tunable) | Use |
|-------|--------------------------------|-----|
| `standard` | `easeOutCubic` *(existing)* | everyday enter |
| `symmetric` | `easeInOut` *(existing)* | reversible moves |
| `emphasized` | `easeInOutCubicEmphasized` (M3) | hero moves (reveal, panels) |
| `emphasizedAccelerate` | `Cubic(0.3, 0.0, 0.8, 0.15)` | hero *exit* |
| `springy` | `Cubic(0.34, 1.26, 0.64, 1.0)` (gentle overshoot) | the *only* place "character" lives — small playful beats |

Exact curve constants are tunable during build against the live gallery; the
table is the intent. `springy` is deliberately a *mild* overshoot, not elastic.

### Disney principles → concrete pieces

| Principle | Where it becomes real |
|-----------|----------------------|
| Slow-in / slow-out | the easing tokens (already the base) |
| Anticipation | a tiny wind-up before a hero move (the mark dips before it blooms) |
| Follow-through / overshoot | the `springy` token, used sparingly |
| Staging | "one focal motion at a time" — already the rule in `StaggeredReflowList`; promoted to a written principle |
| Squash & stretch | press = a ~2–3% scale-down (`PressableScale`); reaction bursts get an elastic pop |
| Arcs / secondary action | floating reactions arc; the launch glow is a secondary action under the wordmark |
| Timing | the duration tokens |

### Reduce motion (one switch, honored everywhere)

- Respect the OS "reduce animations" setting
  (`MediaQuery.disableAnimations`) **and** add a **Settings → Reduce motion**
  toggle (new settings key, mirrors the existing chat-dim/sound settings).
- When on: durations collapse toward instant and all overshoot is dropped —
  content still cross-fades, nothing bounces or rises.
- Exposed via a small `context.reduceMotion` accessor that the primitives read,
  so no screen has to special-case it.
- Hard rule independent of the toggle: no looping/ambient motion plays while
  `PlaybackStatus.playing` (same spirit as the existing idle-dim behavior).

### Reusable primitives (new, small, tested)

- `PressableScale({child, onTap, scale})` — squash-on-press wrapper for
  buttons/icons.
- `RevealIn({child, delay, offset})` — fade + rise (+ optional gentle
  overshoot) for an element entering view.
- `StaggeredReflowList` — *reused as-is* for grouped cascades.
- `LaunchReveal` — the splash widget + its controller (Section B).

Each primitive reads `reduceMotion` and degrades to an instant/fade form.

---

## Section B — Launch reveal + logo (the headline)

### Step 1 — Design the logo (user-driven)

I hand the user a ready-to-paste logo-design prompt (see Appendix A): a
paw-based **mark** + a **"MeowWatch" wordmark**, in ~3 directions, dark-friendly
and vector-friendly. The user generates options and picks one.

### Step 2 — pixel2motion

Run `pixel2motion` on the picked logo. We use:
- its **clean layered logo** (mark / wordmark as separately addressable pieces)
  as the shipped asset, and
- its **browser motion preview** as the shared "yes, that's the feel" reference.

(Its SVG/CSS/GIF output is a *web* format and a *reference* — it is not embedded
in the app.)

### Step 3 — Native rebuild (theme-aware)

Built in Flutter to match the approved feel:

1. The active theme's gradient **washes** across (Cozy / Cinema Noir / Glass
   Aurora — whatever the user has selected).
2. The wordmark **eases in** with a soft letter-stagger; the mark does its small
   **anticipation** dip-then-settle; a quiet **glow** ripples under it (secondary
   action).
3. The wash **dissolves** as the lobby **rises in** behind it — cards + controls
   cascade up reusing the existing list motion — overlapping the dissolve so it
   reads as one continuous motion, not two separate waits.

### Tip line (extensible)

- A small, low-emphasis line fades in **late**, under the wordmark, so it never
  competes with the hero beat.
- First tip = the skip hint: *"click or press any key to skip."*
- Backed by a tiny extensible `LaunchTips` list — future tips drop in one line
  each (e.g. "drag a video anywhere to load," "Tab opens chat"). One tip per
  launch.
- Bonus: if cold start ever runs slow (cold DB warmup), the reveal politely
  holds and the tip is there to read — the splash doubles as a graceful
  "warming up" screen instead of a frozen window.
- Reduce-motion: the tip shows instantly, no fade.

### Behavior rules

- **Cold-start only** (first app open), not on every screen change.
- **Skippable** — any click/key jumps straight to the settled lobby.
- **~1–1.2s** total; **instant** if Reduce motion is on.
- **Never blocks input** — input is live throughout; the reveal *overlaps* real
  app warmup rather than adding a wait.
- **Vector mark** — likely `flutter_svg`, or the mark drawn as a `CustomPainter`
  path; crisp and tintable, no decode cost.

### Assets pipeline (new)

- Add an `assets/brand/` folder + pubspec `assets:` entry.
- Add `flutter_svg` (or commit to a hand-drawn path) — decided at build time
  based on the chosen mark's complexity.

---

## Section C — Surface-by-surface motion (ordered by priority)

**Rule throughout:** one focal motion at a time (staging); nothing ambient
moves while video plays.

### Lobby (high priority)

- **Continue-watching cards** — cascade up on first lobby paint (reuse
  `StaggeredReflowList`; trigger its cascade on entry).
- **Room-join button** — `PressableScale` on press; a small "sending" beat on
  submit.
- **Theme switch** — cross-*fade* the palette instead of an instant snap (a
  quiet echo of the launch wash).
- **Settings gear / panel** — slide + fade open with `emphasized` easing.
- **Lobby → room** — one directional push (slide + fade) instead of the current
  instant swap.

### In-room moments (medium)

- **Friend joins/leaves banner** — slide + fade in, gentle `springy` settle,
  fade-dismiss.
- **Video loaded** — a brief "Loaded — in sync!" reveal.
- **Paw reaction bursts** — elastic pop + arc (the one squash-&-stretch
  character moment).
- **Idle cat mascot** — faint breathing idle; stops the instant video plays.
- **Seek / sync indicator** — smoother directional fade.

### Everyday controls (medium — biggest cumulative polish)

- **Auto-hiding playback bar** — slide + fade with a hint of anticipation on
  hide.
- **Chat expand/collapse** — smooth size + fade, unified on tokens.
- **Buttons / icons** — `PressableScale` + subtle hover lift, app-wide.
- **Volume / seek popups** — consistent fade tokens.

---

## Section D — Showcase / gallery update

- New **"Motion principles"** section: the Disney subset, each a live looping
  specimen (anticipation · overshoot · squash · staging), in the same style as
  the existing `MotionRacer`.
- Specimens for the new tokens (`emphasized`, `springy`, `xfast`, `reveal`).
- Live `PressableScale` + `RevealIn` demos.
- A **"Launch reveal" replay tile** so the splash lives in the design system.
- A **Reduce motion** toggle in the gallery to preview both states.

---

## Section E — Phasing, testing, perf, versioning

### Phases (each its own PR + version bump; `-alpha` kept)

1. **Logo + launch reveal** — user picks logo → pixel2motion → the *minimal*
   foundation tokens the reveal needs (`reveal`, `emphasized`, `springy`,
   reduce-motion switch, `RevealIn`) + native reveal + tip line + content rise.
   *(The "logo first" deliverable.)*
2. **Lobby** — cards cascade, theme cross-fade, gear/panel, lobby→room
   transition.
3. **In-room + controls** — banners, reactions, mascot, playback bar,
   pressables.
4. **Showcase + docs finalize** — motion-principles section, all specimens, an
   `AGENT_GUIDE` motion note.

(Foundation tokens land incrementally with the phase that first needs them, not
as a big upfront dump — though all are documented here.)

### Testing (matches existing repo patterns)

- Widget tests pump the animation and assert end-state + a key mid-frame.
- Golden tests for the reveal frames (the repo already golden-tests chat +
  mascot).
- The reduce-motion path tested (durations → 0, no overshoot).
- Skip-on-input tested (any click/key settles immediately).
- Extend the existing `test/core/theme/tokens/motion_test.dart` and
  `test/ui/gallery/motion_specimen_test.dart`.

### Perf / the one real risk

Startup is this app's tender spot (many hard-won Windows launch-freeze fixes in
`home_screen.dart`). The reveal is therefore built to **never block input**: it
is skippable, it *overlaps* real warmup rather than adding a wait, and it uses a
vector mark (no video decode at frame one). This is a guardrail, called out so
implementation honors it.

### Versioning

Per repo rule, every behavior-changing PR bumps the version in lockstep across
`pubspec.yaml`, `lib/core/app_version.dart`, and `CHANGELOG.md`. Motion phases
are user-visible (mostly minor bumps). Keep `-alpha`.

---

## Open items (resolved during build, not blockers)

- Exact easing curve constants (`emphasized*`, `springy`) — tuned live against
  the gallery.
- `flutter_svg` vs hand-drawn path for the mark — decided once the logo is
  picked (depends on its complexity).
- Whether the lobby→room transition is a custom `PageRouteBuilder` or a shared
  reveal primitive — decided in Phase 2.

---

## Appendix A — Logo design prompt (ready to paste)

> Design a logo for **MeowWatch**, a cozy desktop app for watching videos in
> perfect sync with a friend (co-watching) and chatting over a floating overlay.
> The vibe: warm, friendly, calm, a little playful — but premium and refined,
> not childish. Think the polish of Google/Windows brand marks.
>
> Deliver a **logo system**: a compact **icon mark** built around a **cat paw**
> motif (a paw can double as a "play" gesture or a soft pause/cushion shape —
> explore that overlap), plus a **"MeowWatch" wordmark** in a clean, rounded,
> modern sans-serif. The mark must read clearly at small sizes (app icon / tray)
> and stand alone without the wordmark.
>
> Give me **3 distinct directions**:
> 1. **Cozy / soft** — rounded forms, gentle, warm.
> 2. **Premium / geometric** — crisp, minimal, confident.
> 3. **Playful** — a touch of personality (a wink of motion or a friendly tilt),
>    still tasteful.
>
> Constraints:
> - Works on **dark backgrounds**; deliver on transparent background.
> - **Flat vector** style — no gradients baked in, no photorealism, no 3D — so
>   the mark can be **re-tinted to a single accent color** (it must look right in
>   one color). Primary accent lives in a warm amber/peach family, but keep the
>   shape monochrome-friendly.
> - Mark should be **layerable** (paw / detail / wordmark as separable pieces) so
>   it can later be animated piece by piece.
> - Provide the icon mark alone, the wordmark alone, and the lockup (mark +
>   wordmark) together.
>
> Avoid: clip-art cats, whiskers-everywhere clutter, generic "play triangle in a
> circle," drop shadows, skeuomorphism.
