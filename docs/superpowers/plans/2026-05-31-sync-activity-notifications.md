# Sync Activity Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Announce a peer's play/pause/seek as a transient over-video banner plus a dim chat system line, so each watcher understands why playback jumped.

**Architecture:** A pure classifier turns the Syncplay client's already-applied peer state into an optional `SyncActivity` at the source (race-free, with the pre-apply local snapshot). `SyncCore` republishes these on a new `activity` broadcast stream. `HomeScreen` subscribes and renders each via the existing transient-banner + `chat.addSystem` channels. Drift-rewind corrections are filtered out so only deliberate friend-actions surface.

**Tech Stack:** Flutter/Dart. Run Flutter via the Puro absolute path — plain `flutter` is NOT on PATH:
`FLUTTER=C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`

---

## File Structure

- Create `lib/core/sync/sync_activity.dart` — `classifySyncActivity(...)` pure function.
- Create `lib/ui/sync_activity_text.dart` — pure banner/chat text builder (reuses `formatRuntime`).
- Modify `lib/core/sync/peer_state.dart` — add `SyncActivityKind` enum + `SyncActivity` class.
- Modify `lib/core/sync/sync_core.dart` — add `activity` stream + `emitActivity` + close on dispose.
- Modify `lib/core/sync/syncplay_client.dart` — emit activity in `_handleState`.
- Modify `lib/ui/home_screen.dart` — subscribe; generalize the transient-notice helper; render.
- Create `test/core/sync/sync_activity_test.dart`, `test/ui/sync_activity_text_test.dart`.
- Modify `test/core/sync/sync_core_test.dart` — activity-stream test.
- Modify `pubspec.yaml`, `lib/core/app_version.dart`, `CHANGELOG.md` — version bump.

---

### Task 1: `SyncActivity` data type

**Files:**
- Modify: `lib/core/sync/peer_state.dart` (append at end of file)
- Test: `test/core/sync/peer_state_test.dart` (append cases)

- [ ] **Step 1: Write the failing test**

Append to `test/core/sync/peer_state_test.dart` (add the import if not already present:
`import 'package:meowwatch/core/sync/peer_state.dart';` — it is already imported there):

```dart
  test('SyncActivity equality is value-based over all fields', () {
    const a = SyncActivity(
      kind: SyncActivityKind.paused,
      username: 'lin',
      position: Duration(seconds: 90),
    );
    const b = SyncActivity(
      kind: SyncActivityKind.paused,
      username: 'lin',
      position: Duration(seconds: 90),
    );
    const different = SyncActivity(
      kind: SyncActivityKind.played,
      username: 'lin',
      position: Duration(seconds: 90),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == different, isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/peer_state_test.dart`
Expected: FAIL — `SyncActivity`/`SyncActivityKind` undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

Append to `lib/core/sync/peer_state.dart`:

```dart
/// A deliberate playback action a peer took (play/pause/seek), surfaced as a
/// notification so the other watcher understands why playback jumped. Drift
/// corrections are NOT activities — see classifySyncActivity.
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

  /// Target position of the action (where they paused/seeked to). For [played]
  /// it is the resume point; the UI ignores it there.
  final Duration position;

  @override
  bool operator ==(Object other) =>
      other is SyncActivity &&
      other.kind == kind &&
      other.username == username &&
      other.position == position;

  @override
  int get hashCode => Object.hash(kind, username, position);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/peer_state_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/peer_state.dart test/core/sync/peer_state_test.dart
git commit -m "feat: add SyncActivity data type"
```

---

### Task 2: `classifySyncActivity` pure function

**Files:**
- Create: `lib/core/sync/sync_activity.dart`
- Test: `test/core/sync/sync_activity_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/sync/sync_activity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_activity.dart';

void main() {
  SyncActivity? classify({
    required bool peerPaused,
    required bool localPaused,
    bool doSeek = false,
    Duration peerPos = const Duration(seconds: 100),
    Duration localPos = const Duration(seconds: 100),
    String? setBy = 'lin',
  }) =>
      classifySyncActivity(
        global: PeerPlayState(
          position: peerPos,
          paused: peerPaused,
          doSeek: doSeek,
          setBy: setBy,
        ),
        localPaused: localPaused,
        localPosition: localPos,
      );

  test('pause flip → paused at peer position', () {
    final a = classify(peerPaused: true, localPaused: false);
    expect(a, isNotNull);
    expect(a!.kind, SyncActivityKind.paused);
    expect(a.username, 'lin');
    expect(a.position, const Duration(seconds: 100));
  });

  test('play flip → played', () {
    final a = classify(peerPaused: false, localPaused: true);
    expect(a!.kind, SyncActivityKind.played);
  });

  test('forward seek → seekedForward', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(seconds: 500),
      localPos: const Duration(seconds: 100),
    );
    expect(a!.kind, SyncActivityKind.seekedForward);
    expect(a.position, const Duration(seconds: 500));
  });

  test('backward seek → seekedBack', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(seconds: 30),
      localPos: const Duration(seconds: 100),
    );
    expect(a!.kind, SyncActivityKind.seekedBack);
  });

  test('micro-seek within noise threshold → null', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      doSeek: true,
      peerPos: const Duration(milliseconds: 100600),
      localPos: const Duration(seconds: 100),
    );
    expect(a, isNull);
  });

  test('drift rewind (no flip, no seek) → null', () {
    final a = classify(
      peerPaused: false,
      localPaused: false,
      peerPos: const Duration(seconds: 80),
      localPos: const Duration(seconds: 100),
    );
    expect(a, isNull);
  });

  test('unattributable (setBy null) → null', () {
    final a = classify(peerPaused: true, localPaused: false, setBy: null);
    expect(a, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_activity_test.dart`
Expected: FAIL — `classifySyncActivity` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/sync/sync_activity.dart`:

```dart
import 'peer_state.dart';

/// Classify a followed peer state into a deliberate [SyncActivity], or null
/// when it is not a friend-action worth announcing.
///
/// Fed the relayed [global] state plus our OWN play state captured just BEFORE
/// we apply it — the Syncplay client calls this at the decision point, so the
/// locals are still the pre-jump snapshot (race-free; deriving this in the UI
/// from the applied stream would be timing-fragile).
///
/// Suppressed (→ null):
///   * no [PeerPlayState.setBy] — cannot attribute who did it
///   * a seek landing within [seekNoiseThreshold] of where we already are
///   * a drift rewind: no seek flag and no pause/play flip (the client nudging
///     us back into the room is not a deliberate action).
SyncActivity? classifySyncActivity({
  required PeerPlayState global,
  required bool localPaused,
  required Duration localPosition,
  Duration seekNoiseThreshold = const Duration(seconds: 1),
}) {
  final user = global.setBy;
  if (user == null) return null;

  if (global.doSeek) {
    final delta = global.position - localPosition;
    if (delta.abs() <= seekNoiseThreshold) return null;
    return SyncActivity(
      kind: delta > Duration.zero
          ? SyncActivityKind.seekedForward
          : SyncActivityKind.seekedBack,
      username: user,
      position: global.position,
    );
  }

  if (global.paused != localPaused) {
    return SyncActivity(
      kind: global.paused ? SyncActivityKind.paused : SyncActivityKind.played,
      username: user,
      position: global.position,
    );
  }

  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_activity_test.dart`
Expected: PASS (all 7).

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/sync_activity.dart test/core/sync/sync_activity_test.dart
git commit -m "feat: add classifySyncActivity pure classifier"
```

---

### Task 3: `activity` stream on `SyncCore`

**Files:**
- Modify: `lib/core/sync/sync_core.dart`
- Test: `test/core/sync/sync_core_test.dart`

- [ ] **Step 1: Write the failing test**

In `test/core/sync/sync_core_test.dart`, add a push helper to `FakeSyncCore` (next to the
existing `pushPeer` at line 49):

```dart
  void pushActivity(SyncActivity a) => emitActivity(a);
```

And add this test inside `main()`:

```dart
  test('activity stream emits pushed activities', () async {
    final events = <SyncActivity>[];
    final sub = core.activity.listen(events.add);
    core.pushActivity(const SyncActivity(
      kind: SyncActivityKind.paused,
      username: 'lin',
      position: Duration(seconds: 42),
    ));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events.single.kind, SyncActivityKind.paused);
    expect(events.single.username, 'lin');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_core_test.dart`
Expected: FAIL — `core.activity` / `emitActivity` undefined.

- [ ] **Step 3: Write minimal implementation**

In `lib/core/sync/sync_core.dart`:

Add the controller field after the `_peerFile` controller (line ~19-20):

```dart
  final StreamController<SyncActivity> _activity =
      StreamController<SyncActivity>.broadcast();
```

Add the getter after the `peerFile` getter (line ~30):

```dart
  /// Deliberate peer playback actions (play/pause/seek) to announce.
  Stream<SyncActivity> get activity => _activity.stream;
```

Add the emit helper after `emitPeerFile` (line ~55):

```dart
  @protected
  void emitActivity(SyncActivity a) {
    if (!_disposed) _activity.add(a);
  }
```

Add the close in `dispose()` after `await _peerFile.close();` (line ~97):

```dart
    await _activity.close();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_core_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/sync_core.dart test/core/sync/sync_core_test.dart
git commit -m "feat: add activity stream to SyncCore"
```

---

### Task 4: Emit activity from the Syncplay client

**Files:**
- Modify: `lib/core/sync/syncplay_client.dart` (inside `_handleState`, the `if (action.shouldApply)` block, ~lines 261-275)

No new unit test: `SyncplayClient` drives a live socket and has no test harness; the logic it
delegates to (`classifySyncActivity`) is fully covered by Task 2. Verification is `analyze` +
the existing suite + manual two-instance test.

- [ ] **Step 1: Add the import**

At the top of `lib/core/sync/syncplay_client.dart`, with the other `sync` imports, add:

```dart
import 'sync_activity.dart';
```

- [ ] **Step 2: Emit before adopting the applied state**

Inside `_handleState`, the block currently reads (lines ~261-275):

```dart
      if (action.shouldApply) {
        // Adopt the applied state into our local cache immediately. The video
        // applies it asynchronously, so without this the very next heartbeat
        // would report the STALE pre-apply state (e.g. pos=0 paused=true) and
        // the server would treat that as a brand-new change — the root of the
        // ping-pong fight.
        _localPosition = action.position;
        _localPaused = action.paused;
        emitPeerState(PeerPlayState(
          position: action.position,
          paused: action.paused,
          doSeek: global.doSeek,
          setBy: global.setBy,
        ));
      }
```

Insert the classifier call BEFORE the two `_local*` adoption lines (it needs the pre-apply
snapshot), making the block:

```dart
      if (action.shouldApply) {
        // Surface this as a notification BEFORE we overwrite our local snapshot
        // below — the classifier compares the peer's target to where we were.
        final activity = classifySyncActivity(
          global: global,
          localPaused: _localPaused,
          localPosition: _localPosition,
        );
        if (activity != null) emitActivity(activity);

        // Adopt the applied state into our local cache immediately. The video
        // applies it asynchronously, so without this the very next heartbeat
        // would report the STALE pre-apply state (e.g. pos=0 paused=true) and
        // the server would treat that as a brand-new change — the root of the
        // ping-pong fight.
        _localPosition = action.position;
        _localPaused = action.paused;
        emitPeerState(PeerPlayState(
          position: action.position,
          paused: action.paused,
          doSeek: global.doSeek,
          setBy: global.setBy,
        ));
      }
```

- [ ] **Step 3: Verify it compiles cleanly**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/core/sync/syncplay_client.dart
git commit -m "feat: emit sync activity from Syncplay client"
```

---

### Task 5: Activity text formatter

**Files:**
- Create: `lib/ui/sync_activity_text.dart`
- Test: `test/ui/sync_activity_text_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/sync_activity_text_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/ui/sync_activity_text.dart';

void main() {
  SyncActivityText text(SyncActivityKind kind, Duration pos) =>
      syncActivityText(SyncActivity(
        kind: kind,
        username: 'lin',
        position: pos,
      ));

  test('paused includes position with emoji in banner, plain in chat', () {
    final t = text(SyncActivityKind.paused, const Duration(seconds: 750));
    expect(t.banner, '⏸ lin paused at 12:30');
    expect(t.chatLine, 'lin paused at 12:30');
  });

  test('played omits position', () {
    final t = text(SyncActivityKind.played, const Duration(seconds: 750));
    expect(t.banner, '▶ lin resumed');
    expect(t.chatLine, 'lin resumed');
  });

  test('forward seek wording', () {
    final t = text(SyncActivityKind.seekedForward, const Duration(seconds: 2700));
    expect(t.banner, '⏩ lin skipped to 45:00');
    expect(t.chatLine, 'lin skipped to 45:00');
  });

  test('backward seek wording', () {
    final t = text(SyncActivityKind.seekedBack, const Duration(seconds: 600));
    expect(t.banner, '⏪ lin jumped back to 10:00');
    expect(t.chatLine, 'lin jumped back to 10:00');
  });

  test('over an hour uses h:mm:ss', () {
    final t = text(SyncActivityKind.paused, const Duration(seconds: 3725));
    expect(t.chatLine, 'lin paused at 1:02:05');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/sync_activity_text_test.dart`
Expected: FAIL — `syncActivityText` / `SyncActivityText` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/sync_activity_text.dart`:

```dart
import '../core/sync/peer_state.dart';
import 'connect/history_format.dart';

/// The two strings for a sync activity: an emoji banner over the video and a
/// plain dim line in chat history.
class SyncActivityText {
  const SyncActivityText({required this.banner, required this.chatLine});
  final String banner;
  final String chatLine;
}

/// Build the banner + chat strings for a peer [SyncActivity]. Pure so the
/// wording/edge cases are unit-testable without a widget pump.
SyncActivityText syncActivityText(SyncActivity a) {
  final at = formatRuntime(a.position.inMilliseconds);
  final user = a.username;
  switch (a.kind) {
    case SyncActivityKind.paused:
      return SyncActivityText(
        banner: '⏸ $user paused at $at',
        chatLine: '$user paused at $at',
      );
    case SyncActivityKind.played:
      return SyncActivityText(
        banner: '▶ $user resumed',
        chatLine: '$user resumed',
      );
    case SyncActivityKind.seekedForward:
      return SyncActivityText(
        banner: '⏩ $user skipped to $at',
        chatLine: '$user skipped to $at',
      );
    case SyncActivityKind.seekedBack:
      return SyncActivityText(
        banner: '⏪ $user jumped back to $at',
        chatLine: '$user jumped back to $at',
      );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/ui/sync_activity_text_test.dart`
Expected: PASS (all 5).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/sync_activity_text.dart test/ui/sync_activity_text_test.dart
git commit -m "feat: add sync activity text formatter"
```

---

### Task 6: Wire activity into HomeScreen

**Files:**
- Modify: `lib/ui/home_screen.dart`

Verification is `analyze` + full suite (no new widget test — the rendering reuses the existing
banner + chat-line paths, both already exercised by presence events; the new logic lives in the
already-tested pure helpers).

- [ ] **Step 1: Add the import**

With the other `ui` imports near the top of `lib/ui/home_screen.dart`, add:

```dart
import 'sync_activity_text.dart';
```

- [ ] **Step 2: Add the subscription field**

Next to the other `StreamSubscription` fields (after `_peerFileSub` at line ~68):

```dart
  StreamSubscription<SyncActivity>? _activitySub;
```

- [ ] **Step 3: Generalize the transient-notice helper**

Rename `_showPresenceNotice` to `_showTransientNotice` (line ~304). The body is unchanged; only
the name changes:

```dart
  /// Show a transient banner (friend joined/left, or a sync action); auto-clears
  /// after a few seconds. Call inside setState.
  void _showTransientNotice(String text) {
    _presenceNotice = text;
    _presenceTimer?.cancel();
    _presenceTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _presenceNotice = null);
    });
  }
```

Update the two existing callers in the presence handler (lines ~172, ~178) from
`_showPresenceNotice(` to `_showTransientNotice(`:

```dart
            _showTransientNotice('🐾 ${e.username} joined');
```
```dart
          _showTransientNotice('👋 ${e.username} left');
```

- [ ] **Step 4: Subscribe in initState**

After the `_peerFileSub = _sync.peerFile.listen(...)` block (ends ~line 186), add:

```dart
    _activitySub = _sync.activity.listen((a) {
      if (!mounted) return;
      final t = syncActivityText(a);
      setState(() => _showTransientNotice(t.banner));
      _chat.addSystem(t.chatLine);
    });
```

- [ ] **Step 5: Cancel in dispose**

After `unawaited(_peerFileSub?.cancel());` (line ~228), add:

```dart
    unawaited(_activitySub?.cancel());
```

- [ ] **Step 6: Verify analyze + full suite**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/home_screen.dart
git commit -m "feat: show sync activity notifications in banner and chat"
```

---

### Task 7: Version bump

**Files:**
- Modify: `pubspec.yaml:19`, `lib/core/app_version.dart:4`, `CHANGELOG.md`

- [ ] **Step 1: Bump pubspec**

In `pubspec.yaml` line 19, change:

```yaml
version: 0.3.1-alpha+1
```
to:
```yaml
version: 0.4.0-alpha+1
```

- [ ] **Step 2: Bump app_version**

In `lib/core/app_version.dart` line 4, change:

```dart
const String appVersion = '0.3.1-alpha';
```
to:
```dart
const String appVersion = '0.4.0-alpha';
```

- [ ] **Step 3: Add CHANGELOG entry**

Add a new top entry under the header in `CHANGELOG.md` (match the existing entry format/heading
style already in the file):

```markdown
## [0.4.0-alpha] - 2026-05-31

### Added
- Sync activity notifications: when your friend pauses, resumes, or seeks, a transient banner
  appears over the video and a dim line is logged in chat (e.g. "lin skipped to 45:00") so you
  know why playback jumped.
```

- [ ] **Step 4: Verify analyze + full suite once more**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml lib/core/app_version.dart CHANGELOG.md
git commit -m "chore: bump version to 0.4.0-alpha"
```

---

## Manual test (after implementation)

Build Release (kill running instances first), launch two instances, join the same room, load the
same file. In instance A: pause, resume, seek forward, seek back. In instance B confirm each
shows as a banner over the video AND a chat system line with the right wording/time, and that
your OWN actions in B are NOT announced to yourself. Confirm no spurious notices from drift
corrections during steady playback.
```text
FLUTTER=C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat
Stop-Process -Name meowwatch -Force   # release the file lock first
$FLUTTER build windows
```
