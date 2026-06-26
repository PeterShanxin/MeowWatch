# Lobby motion (Phase 2) — design

- **Date:** 2026-06-26
- **Status:** Approved (brainstorm); plan to follow
- **Owner:** shanxin
- **Parent spec:** `docs/superpowers/specs/2026-06-25-motion-and-launch-reveal-design.md` (§C Lobby, §E phasing). This is Phase 2 of that motion system; Phase 1 (launch reveal + foundation) shipped in 0.36.0-alpha.

## Summary

Phase 2 brings tasteful motion to the lobby (`ConnectScreen`) and adds the
in-app **Reduce motion** switch the rest of the system leans on. It builds on the
Phase 1 foundation already in the tree: the `Motion.*` tokens, the `RevealIn`
fade+rise primitive, the `ReduceMotionScope` + `context.reduceMotion` accessor,
and `StaggeredReflowList`.

**North star (carried from the parent spec):** *motion explains, it does not
perform.* Refined and near-invisible; nothing makes the user wait to watch an
animation; every motion degrades to an instant present under reduce motion.

## Locked decisions (from brainstorm)

- **Scope = 3 new + polish 2.** Build the three genuinely-new motions; verify and
  lightly polish the two lobby motions that already animate today.
- **Cards cascade only at cold-start launch.** After the launch reveal settles,
  the lobby's card sections ripple in once. Returning to the lobby from a room
  does **not** re-cascade (quieter on repeat). Ongoing list add/remove/reorder
  keeps using today's `StaggeredReflowList` reflow.
- **Enter-room transition = fade-up.** The watch screen rises + fades in from
  slightly below (echoes the launch reveal's vocabulary), reversed on leaving.
- **Reduce motion default = off** (motion on). The OS "reduce animations" setting
  still forces it on independently of the switch.

## What already works (so Phase 2 only verifies/polishes it)

Two parent-spec items turned out to be largely implemented:

- **Theme cross-fade.** `MeowColors` is a `ThemeExtension` with a full
  `lerp()` (every color `Color.lerp`-ed, gradient `Gradient.lerp`-ed). `context.meow`
  reads it through `Theme.of(context)`, and `MaterialApp` wraps the tree in
  `AnimatedTheme` (~200 ms). So switching theme already tweens the palette rather
  than snapping. Phase 2 confirms this live and adds the reduce-motion path
  (instant swap when on).
- **Settings gear open.** `LobbySettingsButton` already plays a 160 ms fade +
  downward-slide on open via `TweenAnimationBuilder`. Phase 2 moves its curve to
  the `Motion.emphasized` token and makes it honor reduce motion.

---

## Section A — Reduce motion switch (the keystone)

The switch makes the user's in-app choice flow into the single accessor every
motion primitive already reads, so all motion (this phase's and Phase 1's)
degrades together.

### Persistence + wiring (mirrors how `theme` already flows)

- **New key:** `kReduceMotionSettingKey = 'reduce_motion'` in
  `lib/core/data/settings_store.dart` (value `"true"`/`"false"`, absent → false).
- **Load at startup:** in `main()`, read it next to `savedTheme`
  (`final reduceMotion = (await settings.get(kReduceMotionSettingKey)) == 'true';`)
  and pass it to `MeowWatchApp` as `initialReduceMotion`.
- **App owns the live value:** `MeowWatchApp` holds `_reduceMotion` state and a
  `_setReduceMotion(bool)` that calls `setState` and fire-and-forget persists —
  exactly parallel to `_theme` / `_setTheme`.
- **Scope injected above every route:** `MaterialApp(builder: (context, child) =>
  ReduceMotionScope(reduceMotion: _reduceMotion, child: child!))`, so both the
  lobby and the pushed room route sit under the scope. `context.reduceMotion`
  already ORs the scope with `MediaQuery.disableAnimationsOf`, so OS-on and
  switch-on both win.

### The control (in the shared settings panel)

- A new On/Off row in `SettingsPanel` (`lib/ui/settings/settings_panel.dart`),
  styled like the existing `HistoryModeControl` / `LogLevelControl` segmented
  rows, labelled **"Reduce motion"**. It takes `reduceMotion` + `onChanged` and
  is presentational (value in, callback out), matching the panel's other rows.
- Threaded through both gears that mount `SettingsPanel`: the lobby
  `LobbySettingsButton` and the in-room `PlayerMenuButton`. Both receive the
  value + callback from their screen (`ConnectScreen`, `HomeScreen`), which in
  turn get them from `MeowWatchApp` — the same path `currentTheme` /
  `onThemeChanged` already travel. This keeps the app-root scope and the toggle
  in lockstep and live (flipping it updates motion immediately, everywhere).

---

## Section B — Cards cascade after the splash (cold start only)

When the launch reveal finishes, the lobby's two card sections — **Saved rooms**
and **Continue watching** — ripple in top-to-bottom as one staggered entrance,
once per cold start.

- **Trigger:** the launch reveal already calls `onComplete` exactly once on the
  cold-start settle (and immediately when disabled / reduce motion). `MeowWatchApp`
  flips an entrance signal there and passes it down to `ConnectScreen`, which
  plays the cascade once. Because the reveal is cold-start-only and `onComplete`
  fires once, there is no re-cascade on room return — no re-entry detection
  needed.
- **Mechanism:** a small one-shot staggered-entrance helper built from the
  Phase 1 `RevealIn`, in a new `lib/ui/motion/staggered_reveal.dart`. The ripple
  reads **card-by-card, top-to-bottom**: each lobby card widget (each Saved-rooms
  card and each Continue-watching card) is wrapped in a one-shot `RevealIn` whose
  `delay` increases with the card's position. It plays its fade+rise once when the
  entrance signal arrives, then is inert. Wrapping the individual card *widgets*
  (not the list) means `StaggeredReflowList` keeps owning continue-watching's
  reflow untouched: during the entrance the already-settled reflow list is static
  (its first build is static by design) while the per-card `RevealIn`s supply the
  ripple; after entrance the `RevealIn`s are full-present pass-throughs and later
  data changes reflow exactly as today.
- **Reduce motion:** `RevealIn` already degrades to an instant full-present, so
  the cascade is simply absent when reduce motion is on — cards are there
  immediately.
- **Does not fight the reveal:** on cold start the launch reveal rises the whole
  lobby block in; the card cascade is a deliberate *second* beat that starts as
  the reveal settles (a soft ripple under a now-static form), not a competing
  simultaneous motion.

---

## Section C — Fade-up route into a room

- **New primitive:** `fadeUpRoute<T>({required Widget page})` returning a
  `PageRouteBuilder<T>` in `lib/ui/motion/fade_up_route.dart`. Forward
  transition = fade in + a small upward translate (from ~16 px below to 0),
  on `Motion.emphasized` over a lobby-appropriate duration (`Motion.slow`);
  the reverse plays on pop.
- **Used where the room is pushed:** `app.dart`'s `onConnect` swaps
  `MaterialPageRoute` for `fadeUpRoute(page: HomeScreen(...))`.
- **Reduce motion:** the route detects `context.reduceMotion` and uses a
  zero-duration / no-transform transition (a plain cut) when on.
- **Reusable:** kept generic so Phase 3+ can reuse it for other forward pushes.

---

## Section D — Polish the two that already animate

- **Theme cross-fade:** confirm the `AnimatedTheme` + `MeowColors.lerp` tween is
  visible in each theme pair when building the early look. Add the reduce-motion
  path: when `context.reduceMotion` is on, the swap is instant (no perceived
  fade). Tuning the tween's duration/curve is optional and only if the default
  linear 200 ms reads poorly.
- **Settings gear:** change the open animation's curve from `Motion.standard` to
  `Motion.emphasized`; when reduce motion is on, show the panel with no
  fade/slide (instant).

---

## Architecture / files

**New (small, focused, tested):**

- `lib/ui/motion/fade_up_route.dart` — the page transition primitive.
- `lib/ui/motion/staggered_reveal.dart` — the one-shot entrance cascade wrapper
  over `RevealIn`.

**Modified:**

- `lib/core/data/settings_store.dart` — add `kReduceMotionSettingKey`.
- `lib/main.dart` — load the setting, pass `initialReduceMotion`.
- `lib/app.dart` — `_reduceMotion` state + `_setReduceMotion`; `ReduceMotionScope`
  via `MaterialApp.builder`; entrance signal to `ConnectScreen`; `fadeUpRoute` in
  `onConnect`; thread reduce-motion value/callback to both screens.
- `lib/ui/settings/settings_panel.dart` — the Reduce-motion row.
- `lib/ui/settings/lobby_settings_button.dart` — emphasized curve + reduce-motion;
  pass the new params through.
- `lib/ui/connect/connect_screen.dart` — accept the entrance signal, wrap the
  card sections in the staggered entrance, pass reduce-motion through to the gear.
- `lib/ui/home_screen.dart` + the in-room `PlayerMenuButton` — thread the
  reduce-motion value/callback into the in-room `SettingsPanel`.
- Gallery (`lib/ui/gallery/gallery_sections.dart`) — extend the existing
  reduce-motion note to mention it is now a real app setting; optionally add a
  fade-up route specimen. (Light; not load-bearing.)

Each unit is isolated: the route knows nothing about settings; the entrance
wrapper knows nothing about the reveal beyond a single "play now" trigger; the
toggle is presentational. `StaggeredReflowList` is **not** modified — the
entrance is a separate outer wrapper.

## Testing (matches existing repo patterns)

- **Reduce-motion setting:** flipping the `SettingsPanel` row fires `onChanged`;
  `MeowWatchApp` updates the scope so `context.reduceMotion` becomes true; a
  motion primitive under it shows its instant form. Persistence writes the key.
- **Cascade:** given the entrance signal, the card sections start below/faded and
  settle to full present, staggered; under reduce motion they are present on the
  first frame (no cascade).
- **Fade-up route:** pushing it shows the rise+fade mid-transition and reverses on
  pop; under reduce motion it is an instant cut.
- **Theme swap under reduce motion:** instant (no mid-tween frame).
- **Gear:** opens with the emphasized curve; instant under reduce motion.
- Widget tests assert end-state + a key mid-frame, per the Phase 1 precedent.
  Goldens are out of scope for this phase (the parent spec defers reveal-frame
  goldens; the same applies here).

## Versioning

Per the repo rule, this `feat:` PR is one **MINOR** bump in lockstep:
`pubspec.yaml` → `0.37.0-alpha+1`, `lib/core/app_version.dart` `appVersion` →
`'0.37.0-alpha'`, and a new top `## [0.37.0-alpha] - 2026-06-26` entry in
`CHANGELOG.md` (date = the release day; user-facing notes: "Reduce motion"
setting + the lobby coming alive). Keep the `-alpha` suffix.

## Non-goals (deferred to later phases, per the parent spec §E)

- **In-room + everyday controls** — friend join/leave banners, paw-burst
  reactions, idle mascot, auto-hiding playback bar, app-wide `PressableScale` —
  Phase 3.
- **Motion-principles looping specimens + per-letter wordmark stagger** — Phase 4.
- **Per-element form cascade** (name/buttons) and a theme-switch wash echo — not
  needed for this phase's feel; the form rises with the reveal as one block and
  the palette already cross-fades.
- **Reveal/transition golden tests** — deferred, as in Phase 1.
