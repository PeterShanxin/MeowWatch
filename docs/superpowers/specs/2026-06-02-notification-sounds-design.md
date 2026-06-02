# Notification sounds: redesign + selectable presets (#58)

**Date:** 2026-06-02
**Issue:** [#58](https://github.com/PeterShanxin/MeowWatch/issues/58) (folds in part of [#57](https://github.com/PeterShanxin/MeowWatch/issues/57))
**Type:** feat (MINOR version bump)

## Problem

The app plays one chime (`assets/sounds/notify.wav`) only when the window is
**unfocused** and a new chat arrives. Two problems:

1. The single chime sounds bad.
2. When the window is focused but the chat card is collapsed during playback, a
   new message gives no audible cue at all — you can miss it while watching.
3. (#57) System/sync lines can trigger the chime today, because the sound path
   only checks `username != self`, not whether the message is a system line.

## Goals

- A nicer **primary** sound (attention) for the unfocused case.
- A quieter **secondary** sound (felt-not-heard) for collapsed-while-playing.
- Both **user-selectable** from a short preset list, persisted across runs.
- System/sync lines never make a sound.

Non-goals: per-event sounds beyond these two; volume sliders; custom
user-supplied sound files; sound for reactions/typing.

## Sound assets (locked, pre-synthesized)

Bundled WAVs (44.1 kHz, 16-bit mono), levels tuned by ear with the user:

| Slot      | id          | Label         | File                          | Peak |
|-----------|-------------|---------------|-------------------------------|------|
| Primary   | `marimba` ★ | Wood marimba  | `primary_marimba.wav`         | 0.60 |
| Primary   | `warm_bell` | Warm bell     | `primary_warm_bell.wav`       | 0.60 |
| Primary   | `glass`     | Glass chime   | `primary_glass.wav`           | 0.50 |
| Secondary | `low_thud` ★| Low thud      | `secondary_low_thud.wav`      | 0.92 |
| Secondary | `soft_bell` | Soft bell     | `secondary_soft_bell.wav`     | 0.80 |

★ = default. Loudness is **baked into the asset** (normalized to the peak above),
so playback needs no per-sound volume code and the in-app preview is honest
("real mixed level"). Old `notify.wav` is removed.

Source synth scripts live in `D:\tmp\meow_sounds\` (`final_synth.py`); the
generated finalists are copied into `assets/sounds/` at implementation time.

## Architecture

Follows the existing **commands-in / streams-out + simple key-value settings**
patterns already used for the chat-dim controls.

### 1. Preset data — `lib/core/audio/notify_sounds.dart` (new, pure)

```
@immutable class NotifySound { final String id, label, asset; }

const List<NotifySound> kPrimarySounds   = [...marimba, warm_bell, glass];
const List<NotifySound> kSecondarySounds = [...low_thud, soft_bell];

const String kDefaultPrimarySoundId   = 'marimba';
const String kDefaultSecondarySoundId = 'low_thud';

NotifySound resolvePrimary(String? id)   // id -> sound, falls back to default
NotifySound resolveSecondary(String? id) // "
```

`asset` is the full `asset:///assets/sounds/<file>` URI media_kit expects.
Pure, no Flutter import → unit-testable headless.

### 2. Settings keys — `lib/core/data/settings_store.dart`

```
const kNotifyPrimarySoundKey   = 'notify_primary_sound';   // value = preset id
const kNotifySecondarySoundKey = 'notify_secondary_sound';
```

Same `SettingsStore.get/set(String)` interface as today. No schema/migration —
absent key → default via `resolve*`.

### 3. Playback decision — pure helper `lib/ui/notify_decision.dart` (new)

Extract the "which sound, if any" choice so it is testable without a widget pump:

```
enum NotifyKind { none, primary, secondary }

NotifyKind decideNotify({
  required bool isSystem,      // lastMsg.system
  required bool isOwnMessage,  // lastMsg.username == self
  required bool windowFocused,
  required bool chatCollapsed,
  required bool videoPlaying,
})
```

Rules (in order):
- own message or system line → `none`  *(this is the #57 fix)*
- window **unfocused** → `primary`
- focused + chat **collapsed** + video **playing** → `secondary`
- otherwise (focused + chat open, or paused) → `none`

### 4. Wiring — `lib/ui/home_screen.dart`

- Hold `String _primarySoundId`, `_secondarySoundId` (init to defaults), load in
  `_initSettings()` alongside the dim settings.
- Replace the inline notify block in the `_chat.stream` listener with:
  call `decideNotify(...)` → on `primary`/`secondary`, apply the existing 2s
  `_notifyClock` throttle, then `_audioPlayer.open(Media(resolved.asset), play:true)`.
  `windowManager.isFocused()` is already awaited there.
- Add `_previewSound(String asset)` that plays a preset on demand (reuses
  `_audioPlayer`, ignores the throttle so previews always sound).
- Pass the two ids + `onChanged` (setState + `settings.set`) + `onPreview`
  callbacks into `PlayerMenuButton`, mirroring the dim-setting plumbing.

### 5. UI — `lib/ui/player_menu_button.dart`

Inside the existing collapsible **Settings** section, below the dim controls,
add two rows built from `kPrimarySounds` / `kSecondarySounds`:

- "Notification sound"  → dropdown (current label) + ▶ preview button
- "Quiet sound (chat hidden)" → dropdown + ▶ preview button

A small `_SoundPickerRow` widget: `DropdownButton`/`MenuAnchor` styled to the
Cozy theme (accent text, surface background), preview taps call `onPreview(asset)`.

## Data flow

```
gear → Settings → pick preset
   → onChanged(id) → setState(_xSoundId) + settings.set(key,id)   [persist]
   → ▶ preview     → onPreview(asset) → _audioPlayer plays it now

new peer msg → _chat.stream listener
   → decideNotify(system,own,focused,collapsed,playing)
   → primary/secondary → throttle → _audioPlayer.open(resolve(id).asset)
```

## Testing

- `notify_sounds_test.dart` — resolve\* returns the right sound; unknown/null id
  falls back to default; every preset asset path is well-formed.
- `notify_decision_test.dart` — full truth table over the 5 inputs
  (system, own, focused, collapsed, playing) → expected `NotifyKind`,
  including the #57 system-line case.
- `player_menu_button` widget test — both picker rows render, changing a
  dropdown fires `onChanged`, preview button fires `onPreview`.
- Manual two-instance check (visible behavior) before tagging the release.

## Versioning

feat → MINOR bump in lockstep: `pubspec.yaml`, `lib/core/app_version.dart`,
`CHANGELOG.md` (keep `-alpha`).

## Files touched

- **new** `lib/core/audio/notify_sounds.dart`
- **new** `lib/ui/notify_decision.dart`
- **new** `test/core/audio/notify_sounds_test.dart`
- **new** `test/ui/notify_decision_test.dart`
- edit `lib/core/data/settings_store.dart` (2 keys)
- edit `lib/ui/home_screen.dart` (state, init, listener rework, preview, plumbing)
- edit `lib/ui/player_menu_button.dart` (2 picker rows + widget)
- edit `pubspec.yaml` (assets dir; version)
- edit `lib/core/app_version.dart`, `CHANGELOG.md` (version)
- **assets** add 5 WAVs to `assets/sounds/`, remove `notify.wav`
