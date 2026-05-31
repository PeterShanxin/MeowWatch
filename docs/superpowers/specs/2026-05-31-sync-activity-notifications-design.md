# Sync Activity Notifications — Design

**Issue:** [#4 Sync activity notifications (Status messages)](https://github.com/PeterShanxin/MeowWatch/issues/4)
**Date:** 2026-05-31
**Type:** `feat:` → MINOR version bump (`0.3.1-alpha` → `0.4.0-alpha`)

## Goal

When your friend pauses, resumes, or seeks, surface *who did what* so you understand
why playback jumped. Show each event as a transient banner over the video **and** a dim
system line in chat history — the same two-channel pattern presence ("X joined") already uses.

Scope: **peer actions only**. You already know what you did; your own play/pause/seek stay
silent. (`decideFollow` never emits for self-set changes, so this falls out naturally.)

## Where events come from

The Syncplay client already decides "should I follow this peer change?" in `decideFollow`,
inside `SyncplayClient._handleState`. That decision point has everything needed, race-free:

- `global.setBy` — who did it
- `global.paused` — the peer's new paused state
- `global.doSeek` — whether it was a seek
- `global.position` — the target position
- `_localPaused` / `_localPosition` — **our** state right before we apply the change

Classifying here (at the source) avoids the timing races that deriving from the `peerState`
stream in the UI would hit — by the time the UI sees an applied state, the video may have
already moved, making "real pause vs. drift-correction?" unreliable.

### The drift-rewind filter

`decideFollow` also applies **drift rewinds** (rule 3: nudge us back when we've run ahead of
the room). These carry `doSeek == false` and **no** paused flip — they are not deliberate
friend-actions and must be **suppressed** (never become a toast). The classifier distinguishes
them: a non-seek event whose `paused` equals our local `paused` is a drift correction → `null`.

## New pieces

### 1. Data type (`lib/core/sync/peer_state.dart`)

```dart
enum SyncActivityKind { played, paused, seekedForward, seekedBack }

@immutable
class SyncActivity {
  const SyncActivity({
    required this.kind,
    required this.username,
    required this.position,
  });
  final SyncActivityKind kind;
  final String username;
  final Duration position; // target/current position at the event
  // == / hashCode over all three fields.
}
```

### 2. Pure classifier (`lib/core/sync/sync_activity.dart`)

```dart
SyncActivity? classifySyncActivity({
  required PeerPlayState global,   // the peer's relayed state
  required bool localPaused,       // our paused state BEFORE applying
  required Duration localPosition, // our position BEFORE applying
  Duration seekNoiseThreshold = const Duration(seconds: 1),
});
```

Rules, in order:
1. `global.setBy == null` → `null` (cannot attribute).
2. `global.doSeek == true`:
   - delta = `global.position - localPosition`
   - `|delta| <= seekNoiseThreshold` → `null` (micro-seek noise)
   - delta > 0 → `seekedForward`; else → `seekedBack`
   - `position = global.position`
3. `global.paused != localPaused` → `paused` (if now paused) or `played`;
   `position = global.position`.
4. else → `null` (drift rewind / steady heartbeat).

Headless-testable, mirroring how `sync_follow.dart` / `chat_corner.dart` split pure logic out.

### 3. Activity stream on `SyncCore` (`lib/core/sync/sync_core.dart`)

Same shape as the existing `presence` / `chat` streams:

```dart
final StreamController<SyncActivity> _activity =
    StreamController<SyncActivity>.broadcast();
Stream<SyncActivity> get activity => _activity.stream;

@protected
void emitActivity(SyncActivity a) { if (!_disposed) _activity.add(a); }
```

Closed in `dispose()` alongside the other controllers.

### 4. Client emits it (`lib/core/sync/syncplay_client.dart`)

In `_handleState`, **before** adopting the applied state into `_localPaused` / `_localPosition`
(the classifier needs the pre-apply snapshot), and gated on `action.shouldApply`:

```dart
final activity = classifySyncActivity(
  global: global,
  localPaused: _localPaused,
  localPosition: _localPosition,
);
if (activity != null) emitActivity(activity);
```

Placed inside the existing `if (action.shouldApply) { ... }` block (we only narrate changes we
actually follow), reading the locals before they are overwritten.

## UI wiring (`lib/ui/home_screen.dart`)

- Subscribe to `_sync.activity` in `initState`; cancel in `dispose`.
- On each event (inside `setState`):
  - show transient banner — **generalize** the existing `_showPresenceNotice` into a shared
    `_showTransientNotice(text)` (presence keeps using it); banner text includes emoji.
  - append a dim chat line via `_chat.addSystem(chatLine)`.
- The banner priority chain in `_banner` is unchanged — the transient notice slot already sits
  at the top, so an activity toast briefly overrides the file-mismatch / waiting hints, then
  auto-clears (existing 3s timer) back to whatever is underneath.

### Text formatting (`lib/ui/sync_activity_text.dart`)

Pure helper returning the banner + chat strings, reusing `formatRuntime` for `mm:ss` / `h:mm:ss`.
Kept out of the widget so wording is unit-testable.

| Kind | Banner | Chat line |
|---|---|---|
| `paused` | `⏸ lin paused at 12:30` | `lin paused at 12:30` |
| `played` | `▶ lin resumed` | `lin resumed` |
| `seekedForward` | `⏩ lin skipped to 45:00` | `lin skipped to 45:00` |
| `seekedBack` | `⏪ lin jumped back to 10:00` | `lin jumped back to 10:00` |

`played` omits a position (resume continues from the paused point — a number adds nothing).

## Testing (TDD: RED → GREEN → REFACTOR)

1. **`test/core/sync/sync_activity_test.dart`** — the classifier:
   - paused flip → `paused`; play flip → `played`
   - `doSeek` forward → `seekedForward`; backward → `seekedBack`
   - micro-seek within threshold → `null`
   - drift rewind (no flip, `doSeek == false`) → `null`
   - `setBy == null` → `null`
2. **`test/ui/sync_activity_text_test.dart`** — wording for all four kinds, including `h:mm:ss`
   at/over an hour and `played` having no position.
3. Existing `SyncCore` fake / any `peer_state` tests updated if the new stream needs a stub
   close. No goldens (no new pixel-rendered widget).

## Out of scope (YAGNI)

- No own-action narration, no settings toggle to disable, no per-event sound.
- No de-duplication/rate-limiting beyond the micro-seek filter — deliberate friend actions are
  infrequent enough that each deserves a line.

## Version bump

Lockstep across `pubspec.yaml` (`0.4.0-alpha+1`), `lib/core/app_version.dart`
(`0.4.0-alpha`), and a new `CHANGELOG.md` top entry `## [0.4.0-alpha] - 2026-05-31`.
