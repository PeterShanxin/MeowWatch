# Notification Sounds: Redesign + Selectable Presets — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single notification chime with two user-selectable, nicer sounds — a loud "primary" for an unfocused window and a quiet "secondary" for collapsed-while-playing — and stop system lines from chiming (#57).

**Architecture:** Two new pure modules — a preset table (`notify_sounds.dart`) and a `decideNotify` truth-table helper (`notify_decision.dart`) — keep all logic headless-testable. `HomeScreen` loads two new key-value settings, calls `decideNotify` in the chat-stream listener, and plays the resolved asset through the existing `media_kit` `Player`. The gear → Settings panel gains two dropdown+preview rows.

**Tech Stack:** Flutter (desktop), `media_kit` (`Player`/`Media`), Drift-backed `SettingsStore` (string key-value), `flutter_test`.

**Flutter binary:** `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat` (NOT on PATH). Set `FLUTTER=%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat` for commands below.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `lib/core/audio/notify_sounds.dart` *(new)* | Immutable `NotifySound`, the two preset lists, default ids, `resolvePrimary`/`resolveSecondary`. Pure. |
| `lib/ui/notify_decision.dart` *(new)* | `NotifyKind` enum + `decideNotify(...)` pure decision. |
| `lib/core/data/settings_store.dart` | Add two setting-key constants. |
| `lib/ui/home_screen.dart` | Hold/load the two ids; rework the chat listener to use `decideNotify`; add `_previewSound`; plumb ids/callbacks to the menu. |
| `lib/ui/player_menu_button.dart` | Two `_SoundPickerRow` (dropdown + ▶ preview) in the Settings section. |
| `pubspec.yaml` | Register `assets/sounds/` dir; bump version. |
| `lib/core/app_version.dart`, `CHANGELOG.md` | Version bump. |
| `assets/sounds/*.wav` | Add 5 finalists; remove `notify.wav`. |
| `test/core/audio/notify_sounds_test.dart` *(new)* | Preset resolution + asset-path shape. |
| `test/ui/notify_decision_test.dart` *(new)* | Decision truth table incl. #57. |
| `test/ui/player_menu_sound_picker_test.dart` *(new)* | Picker rows render + fire callbacks. |

---

## Task 1: Install the sound assets

**Files:**
- Create: `assets/sounds/primary_marimba.wav`, `primary_warm_bell.wav`, `primary_glass.wav`, `secondary_low_thud.wav`, `secondary_soft_bell.wav`
- Delete: `assets/sounds/notify.wav`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Copy the generated finalists into the repo**

The locked WAVs live in `D:\tmp\meow_sounds\final\`. Copy the 5 files and delete the old chime:

```powershell
Copy-Item D:\tmp\meow_sounds\final\primary_marimba.wav    D:\Repos\MeowWatch\assets\sounds\
Copy-Item D:\tmp\meow_sounds\final\primary_warm_bell.wav  D:\Repos\MeowWatch\assets\sounds\
Copy-Item D:\tmp\meow_sounds\final\primary_glass.wav      D:\Repos\MeowWatch\assets\sounds\
Copy-Item D:\tmp\meow_sounds\final\secondary_low_thud.wav D:\Repos\MeowWatch\assets\sounds\
Copy-Item D:\tmp\meow_sounds\final\secondary_soft_bell.wav D:\Repos\MeowWatch\assets\sounds\
Remove-Item D:\Repos\MeowWatch\assets\sounds\notify.wav
```

Expected: `assets/sounds/` now holds exactly the 5 new WAVs.

- [ ] **Step 2: Register the assets directory in pubspec**

In `pubspec.yaml`, replace the single-file entry:

```yaml
  assets:
    - assets/sounds/notify.wav
```

with the directory:

```yaml
  assets:
    - assets/sounds/
```

- [ ] **Step 3: Commit**

```bash
git add assets/sounds pubspec.yaml
git commit -m "feat: add notification sound assets, drop old notify.wav (#58)"
```

---

## Task 2: Preset data module (`notify_sounds.dart`)

**Files:**
- Create: `lib/core/audio/notify_sounds.dart`
- Test: `test/core/audio/notify_sounds_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/audio/notify_sounds.dart';

void main() {
  test('default ids resolve to the starred presets', () {
    expect(resolvePrimary(kDefaultPrimarySoundId).id, 'marimba');
    expect(resolveSecondary(kDefaultSecondarySoundId).id, 'low_thud');
  });

  test('unknown or null id falls back to the default', () {
    expect(resolvePrimary('nope').id, kDefaultPrimarySoundId);
    expect(resolvePrimary(null).id, kDefaultPrimarySoundId);
    expect(resolveSecondary('nope').id, kDefaultSecondarySoundId);
    expect(resolveSecondary(null).id, kDefaultSecondarySoundId);
  });

  test('a known non-default id resolves to itself', () {
    expect(resolvePrimary('glass').id, 'glass');
    expect(resolveSecondary('soft_bell').id, 'soft_bell');
  });

  test('every preset asset is a well-formed sounds URI', () {
    for (final s in [...kPrimarySounds, ...kSecondarySounds]) {
      expect(s.asset, startsWith('asset:///assets/sounds/'));
      expect(s.asset, endsWith('.wav'));
      expect(s.label, isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/core/audio/notify_sounds_test.dart`
Expected: FAIL — `notify_sounds.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/foundation.dart';

/// One selectable notification sound: a stable [id] (persisted), a human
/// [label] for the picker, and the media_kit [asset] URI to play.
@immutable
class NotifySound {
  const NotifySound({required this.id, required this.label, required this.asset});

  final String id;
  final String label;
  final String asset;
}

NotifySound _sound(String id, String label, String file) =>
    NotifySound(id: id, label: label, asset: 'asset:///assets/sounds/$file');

/// Loud, attention-grabbing sounds (played when the window is unfocused).
/// First entry is the default.
const List<NotifySound> kPrimarySounds = <NotifySound>[
  // const can't call a function, so spell the URIs out here.
  NotifySound(id: 'marimba', label: 'Wood marimba',
      asset: 'asset:///assets/sounds/primary_marimba.wav'),
  NotifySound(id: 'warm_bell', label: 'Warm bell',
      asset: 'asset:///assets/sounds/primary_warm_bell.wav'),
  NotifySound(id: 'glass', label: 'Glass chime',
      asset: 'asset:///assets/sounds/primary_glass.wav'),
];

/// Quiet, felt-not-heard sounds (chat collapsed while playing). First = default.
const List<NotifySound> kSecondarySounds = <NotifySound>[
  NotifySound(id: 'low_thud', label: 'Low thud',
      asset: 'asset:///assets/sounds/secondary_low_thud.wav'),
  NotifySound(id: 'soft_bell', label: 'Soft bell',
      asset: 'asset:///assets/sounds/secondary_soft_bell.wav'),
];

const String kDefaultPrimarySoundId = 'marimba';
const String kDefaultSecondarySoundId = 'low_thud';

NotifySound _resolve(List<NotifySound> list, String? id, String defaultId) {
  for (final s in list) {
    if (s.id == id) return s;
  }
  return list.firstWhere((s) => s.id == defaultId);
}

/// Resolve a persisted primary id to its sound; unknown/null → default.
NotifySound resolvePrimary(String? id) =>
    _resolve(kPrimarySounds, id, kDefaultPrimarySoundId);

/// Resolve a persisted secondary id to its sound; unknown/null → default.
NotifySound resolveSecondary(String? id) =>
    _resolve(kSecondarySounds, id, kDefaultSecondarySoundId);
```

> Note: `_sound` helper is shown for intent but unused by the `const` lists (a
> `const` initializer can't call a function). Delete `_sound` to avoid an unused
> warning, or keep the lists spelled out as above and remove the helper.

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/core/audio/notify_sounds_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze + commit**

```bash
$FLUTTER analyze lib/core/audio/notify_sounds.dart
git add lib/core/audio/notify_sounds.dart test/core/audio/notify_sounds_test.dart
git commit -m "feat: notification sound preset table + resolver (#58)"
```

---

## Task 3: Decision helper (`notify_decision.dart`)

**Files:**
- Create: `lib/ui/notify_decision.dart`
- Test: `test/ui/notify_decision_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/notify_decision.dart';

NotifyKind call({
  bool isSystem = false,
  bool isOwn = false,
  bool focused = false,
  bool collapsed = false,
  bool playing = false,
}) =>
    decideNotify(
      isSystem: isSystem,
      isOwnMessage: isOwn,
      windowFocused: focused,
      chatCollapsed: collapsed,
      videoPlaying: playing,
    );

void main() {
  test('own message never sounds', () {
    expect(call(isOwn: true, focused: false), NotifyKind.none);
  });

  test('system line never sounds (#57)', () {
    expect(call(isSystem: true, focused: false), NotifyKind.none);
    expect(call(isSystem: true, focused: true, collapsed: true, playing: true),
        NotifyKind.none);
  });

  test('unfocused peer message → primary', () {
    expect(call(focused: false), NotifyKind.primary);
    expect(call(focused: false, collapsed: true, playing: true),
        NotifyKind.primary);
  });

  test('focused + collapsed + playing → secondary', () {
    expect(call(focused: true, collapsed: true, playing: true),
        NotifyKind.secondary);
  });

  test('focused but chat open → none', () {
    expect(call(focused: true, collapsed: false, playing: true),
        NotifyKind.none);
  });

  test('focused + collapsed but paused → none', () {
    expect(call(focused: true, collapsed: true, playing: false),
        NotifyKind.none);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/ui/notify_decision_test.dart`
Expected: FAIL — `notify_decision.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Which notification sound (if any) a freshly-arrived chat message should play.
enum NotifyKind { none, primary, secondary }

/// Decide the sound for a new message. Order matters:
/// 1. our own message or a system/sync line is silent (the #57 fix);
/// 2. an unfocused window gets the loud primary;
/// 3. a focused window only sounds when the chat is collapsed AND the video is
///    playing — a quiet secondary so a message is felt without yanking the eye
///    off the video. Focused-with-chat-open, or paused, stays silent.
NotifyKind decideNotify({
  required bool isSystem,
  required bool isOwnMessage,
  required bool windowFocused,
  required bool chatCollapsed,
  required bool videoPlaying,
}) {
  if (isSystem || isOwnMessage) return NotifyKind.none;
  if (!windowFocused) return NotifyKind.primary;
  if (chatCollapsed && videoPlaying) return NotifyKind.secondary;
  return NotifyKind.none;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/ui/notify_decision_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Analyze + commit**

```bash
$FLUTTER analyze lib/ui/notify_decision.dart
git add lib/ui/notify_decision.dart test/ui/notify_decision_test.dart
git commit -m "feat: pure decideNotify helper for primary/secondary sound (#58)"
```

---

## Task 4: Settings keys

**Files:**
- Modify: `lib/core/data/settings_store.dart`

- [ ] **Step 1: Add the two key constants**

Append after `kChatIdleDimSettingKey` (before `abstract class SettingsStore`):

```dart
/// Key for the persisted primary notification sound (value = a NotifySound id
/// from [kPrimarySounds]; absent/unknown → [kDefaultPrimarySoundId]).
const String kNotifyPrimarySoundKey = 'notify_primary_sound';

/// Key for the persisted secondary (quiet) notification sound (value = a
/// NotifySound id from [kSecondarySounds]; absent/unknown → default).
const String kNotifySecondarySoundKey = 'notify_secondary_sound';
```

- [ ] **Step 2: Analyze + commit**

```bash
$FLUTTER analyze lib/core/data/settings_store.dart
git add lib/core/data/settings_store.dart
git commit -m "feat: settings keys for notify sound presets (#58)"
```

---

## Task 5: Sound picker UI in the gear menu

**Files:**
- Modify: `lib/ui/player_menu_button.dart`
- Test: `test/ui/player_menu_sound_picker_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/audio/notify_sounds.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/player_menu_button.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: MeowThemeScope(
          theme: meowThemeOf(MeowThemeId.cozy),
          child: Scaffold(body: child),
        ),
      );

  testWidgets('picker rows render and fire onChanged / onPreview',
      (tester) async {
    String? changedPrimary;
    String? previewed;

    await tester.pumpWidget(host(
      SoundPickerRow(
        key: const Key('primary-sound-picker'),
        title: 'Notification sound',
        options: kPrimarySounds,
        currentId: kDefaultPrimarySoundId,
        onChanged: (id) => changedPrimary = id,
        onPreview: (asset) => previewed = asset,
      ),
    ));

    // Preview the current selection.
    await tester.tap(find.byKey(const Key('primary-sound-picker-preview')));
    await tester.pump();
    expect(previewed, resolvePrimary(kDefaultPrimarySoundId).asset);

    // Open the dropdown and pick a different option.
    await tester.tap(find.byKey(const Key('primary-sound-picker-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Glass chime').last);
    await tester.pumpAndSettle();
    expect(changedPrimary, 'glass');
  });
}
```

> If `MeowThemeScope`/`meowThemeOf` names differ, match the helpers used by the
> existing `player_menu_button` tests (check `test/ui/` for the current pattern)
> — the assertions on keys/callbacks stay the same.

- [ ] **Step 2: Run test to verify it fails**

Run: `$FLUTTER test test/ui/player_menu_sound_picker_test.dart`
Expected: FAIL — `SoundPickerRow` undefined.

- [ ] **Step 3: Add the `SoundPickerRow` widget + wire it into the panel**

At the top of `player_menu_button.dart`, add the import:

```dart
import '../core/audio/notify_sounds.dart';
```

Add new constructor params to `PlayerMenuButton` and `_MenuPanel` (mirror the
existing `chatIdleDim` plumbing — field, constructor `required this.x`, and pass
through in `PlayerMenuButton.build` → `_MenuPanel`):

```dart
  final String primarySoundId;
  final ValueChanged<String> onPrimarySoundChanged;
  final String secondarySoundId;
  final ValueChanged<String> onSecondarySoundChanged;
  final ValueChanged<String> onPreviewSound; // receives the asset URI
```

Inside `_MenuPanelState.build`, in the expanded Settings `Column` (after the
`_DimSlider`/auto-dim block, still inside the `_settingsOpen` column), add:

```dart
                      const SizedBox(height: 4),
                      SoundPickerRow(
                        key: const Key('primary-sound-picker'),
                        title: 'Notification sound',
                        options: kPrimarySounds,
                        currentId: widget.primarySoundId,
                        onChanged: widget.onPrimarySoundChanged,
                        onPreview: widget.onPreviewSound,
                      ),
                      SoundPickerRow(
                        key: const Key('secondary-sound-picker'),
                        title: 'Quiet sound (chat hidden)',
                        options: kSecondarySounds,
                        currentId: widget.secondarySoundId,
                        onChanged: widget.onSecondarySoundChanged,
                        onPreview: widget.onPreviewSound,
                      ),
```

Add the widget itself (public so the test can construct it directly):

```dart
/// A labelled dropdown of notify-sound presets with a ▶ preview button.
/// Picking fires [onChanged] with the preset id; preview fires [onPreview]
/// with the selected preset's asset URI.
class SoundPickerRow extends StatelessWidget {
  const SoundPickerRow({
    required this.title,
    required this.options,
    required this.currentId,
    required this.onChanged,
    required this.onPreview,
    super.key,
  });

  final String title;
  final List<NotifySound> options;
  final String currentId;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onPreview;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final current =
        options.firstWhere((s) => s.id == currentId, orElse: () => options.first);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: m.textDim, fontSize: 13)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: Key('${_slug()}-dropdown'),
                    value: current.id,
                    isDense: true,
                    dropdownColor: m.surface,
                    iconEnabledColor: m.accent,
                    style: TextStyle(color: m.textPrimary, fontSize: 15),
                    items: [
                      for (final s in options)
                        DropdownMenuItem<String>(
                          value: s.id,
                          child: Text(s.label),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) onChanged(id);
                    },
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('${_slug()}-preview'),
            tooltip: 'Preview',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.play_circle_outline, size: 20, color: m.accent),
            onPressed: () => onPreview(current.asset),
          ),
        ],
      ),
    );
  }

  // Key prefix derived from the widget's own Key so the dropdown/preview keys
  // are stable and match the test (e.g. 'primary-sound-picker').
  String _slug() => (key is ValueKey<String>)
      ? (key as ValueKey<String>).value
      : 'sound-picker';
}
```

> `Key('primary-sound-picker')` is a `ValueKey<String>`, so `_slug()` returns
> `'primary-sound-picker'` and the child keys become
> `primary-sound-picker-dropdown` / `-preview`, matching the test.

- [ ] **Step 4: Run test to verify it passes**

Run: `$FLUTTER test test/ui/player_menu_sound_picker_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
$FLUTTER analyze lib/ui/player_menu_button.dart
git add lib/ui/player_menu_button.dart test/ui/player_menu_sound_picker_test.dart
git commit -m "feat: sound preset picker rows in gear Settings (#58)"
```

---

## Task 6: Wire HomeScreen — state, load, listener, preview, plumbing

**Files:**
- Modify: `lib/ui/home_screen.dart`

- [ ] **Step 1: Add imports + state + replace the old asset constant**

Add imports near the existing ones:

```dart
import '../core/audio/notify_sounds.dart';
import 'notify_decision.dart';
```

Remove the old constant (line ~71):

```dart
  static const String _notifySoundAsset = 'asset:///assets/sounds/notify.wav';
```

Add selected-preset state near `_chatIdleDim` (line ~173):

```dart
  String _primarySoundId = kDefaultPrimarySoundId;
  String _secondarySoundId = kDefaultSecondarySoundId;
```

- [ ] **Step 2: Load the saved ids in `_initSettings()`**

Append inside `_initSettings()` (after the dim block, line ~342):

```dart
    final primary = await widget.settings.get(kNotifyPrimarySoundKey);
    final secondary = await widget.settings.get(kNotifySecondarySoundKey);
    if (mounted) {
      setState(() {
        _primarySoundId = resolvePrimary(primary).id;
        _secondarySoundId = resolveSecondary(secondary).id;
      });
    }
```

- [ ] **Step 3: Rework the chat listener to use `decideNotify`**

Replace lines ~204–221 (the `if (isNewMessage && lastMsg != null ...)` block)
with:

```dart
      if (isNewMessage && lastMsg != null && lastMsg.username != _username) {
        // Real peer chat (not a system/sync line) wakes the dimmed card, which
        // then settles back out — so a brighten never lingers forever.
        if (!lastMsg.system) _wakeChatThenReArmDeepIdle();

        final focused = await windowManager.isFocused();
        if (!mounted) return;
        final kind = decideNotify(
          isSystem: lastMsg.system,
          isOwnMessage: lastMsg.username == _username,
          windowFocused: focused,
          chatCollapsed: _chatLayout.collapsed,
          videoPlaying: _core.state.status == PlaybackStatus.playing,
        );
        if (kind == NotifyKind.none) return;
        if (_notifyClock.isRunning && _notifyClock.elapsed < _notifyThrottle) {
          return;
        }
        _notifyClock
          ..reset()
          ..start();
        final asset = kind == NotifyKind.primary
            ? resolvePrimary(_primarySoundId).asset
            : resolveSecondary(_secondarySoundId).asset;
        try {
          await _audioPlayer.open(Media(asset), play: true);
        } catch (e) {
          debugPrint('Failed to play notification: $e');
        }
      }
```

- [ ] **Step 4: Add a preview method**

Add near `_pulsePeek` (line ~471):

```dart
  /// Play a preset on demand for the Settings preview. Bypasses the notify
  /// throttle so a preview always sounds, but reuses the same player.
  Future<void> _previewSound(String asset) async {
    try {
      await _audioPlayer.open(Media(asset), play: true);
    } catch (e) {
      debugPrint('Failed to preview sound: $e');
    }
  }
```

- [ ] **Step 5: Plumb the new params into `PlayerMenuButton`**

In the `PlayerMenuButton(...)` call (line ~834), after `onChatIdleDimChanged`,
add:

```dart
                          primarySoundId: _primarySoundId,
                          onPrimarySoundChanged: (id) {
                            setState(() => _primarySoundId = id);
                            widget.settings.set(kNotifyPrimarySoundKey, id);
                          },
                          secondarySoundId: _secondarySoundId,
                          onSecondarySoundChanged: (id) {
                            setState(() => _secondarySoundId = id);
                            widget.settings.set(kNotifySecondarySoundKey, id);
                          },
                          onPreviewSound: _previewSound,
```

- [ ] **Step 6: Analyze the whole app + run the full suite**

Run: `$FLUTTER analyze`
Expected: `No issues found!`

Run: `$FLUTTER test`
Expected: all tests pass (new + existing).

- [ ] **Step 7: Commit**

```bash
git add lib/ui/home_screen.dart
git commit -m "feat: play selectable primary/secondary notify sounds; gate system lines (#57, #58)"
```

---

## Task 7: Version bump + changelog

**Files:**
- Modify: `pubspec.yaml`, `lib/core/app_version.dart`, `CHANGELOG.md`

- [ ] **Step 1: Read the current version**

Run: `$FLUTTER --version` is irrelevant; instead read the version line:

```bash
grep -m1 "^version:" pubspec.yaml
grep "appVersion" lib/core/app_version.dart
```

This is a `feat:` → **MINOR** bump (2nd digit +1, reset PATCH to 0), keep
`-alpha`. Example: `0.7.3-alpha` → `0.8.0-alpha`. Use the actual current value.

- [ ] **Step 2: Update all three in lockstep**

- `pubspec.yaml`: `version: <new>+<build>` (bump build number too if present).
- `lib/core/app_version.dart`: `const appVersion = '<new>';`
- `CHANGELOG.md`: new top entry:

```markdown
## [<new>] - 2026-06-02

### Added
- Redesigned notification sounds with selectable presets: a louder "primary"
  chime (Wood marimba / Warm bell / Glass chime) for when the window is in the
  background, and a quieter "secondary" sound (Low thud / Soft bell) felt when
  the chat is collapsed during playback. Pick either in gear → Settings, with a
  preview button. (#58)

### Fixed
- System/sync lines no longer trigger the notification sound. (#57)
```

- [ ] **Step 3: Verify lockstep + analyze**

Run: `$FLUTTER analyze`
Expected: `No issues found!`. Confirm the version string matches across all
three files.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml lib/core/app_version.dart CHANGELOG.md
git commit -m "chore: bump version for notification sound presets (#58)"
```

---

## Task 8: Manual verification (gate before release)

- [ ] **Step 1: Kill running instances, build Release**

```powershell
Stop-Process -Name meowwatch -Force -ErrorAction SilentlyContinue
```
Run: `$FLUTTER build windows`
Verify the artifact: `build/windows/x64/runner/Release/meowwatch.exe` and that
`build/windows/x64/runner/Release/data/app.so` mtime is fresh.

- [ ] **Step 2: Two-instance check**

Launch two Release instances, join the same room, load the same video (software
decode is already forced). Confirm:
- gear → Settings shows both pickers; previews play at the expected loudness.
- Background window + peer message → primary sound.
- Focused, chat collapsed, video playing + peer message → quiet secondary.
- Focused, chat open → silence.
- A system/sync line (e.g. peer pause/seek) → silence (#57).
- Selection persists after restart.

- [ ] **Step 3: Get user confirmation**

Per CLAUDE.md, don't tag the phase/feature complete until the user confirms the
two-instance manual test passes.

---

## Self-Review

- **Spec coverage:** assets (T1), preset table (T2), decision incl. #57 (T3),
  settings keys (T4), picker UI (T5), wiring+preview (T6), version (T7), manual
  gate (T8) — every spec section maps to a task. ✓
- **Type consistency:** `NotifySound{id,label,asset}`, `resolvePrimary`/
  `resolveSecondary`, `NotifyKind{none,primary,secondary}`, `decideNotify(...)`,
  `SoundPickerRow`, keys `kNotify{Primary,Secondary}SoundKey`,
  `kDefault{Primary,Secondary}SoundId` — used identically across T2–T6. ✓
- **Placeholders:** none — every code step shows full code. The two flagged
  caveats (`_sound` unused; theme-host helper names) tell the engineer exactly
  what to confirm. ✓
