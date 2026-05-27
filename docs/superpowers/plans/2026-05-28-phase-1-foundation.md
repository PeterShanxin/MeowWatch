# Phase 1: Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the Flutter desktop app, integrate libmpv via `media_kit`, and play a local video file dropped into the window. No chat, no sync, no theming yet — just a working video player.

**Architecture:** Flutter desktop app with a clean separation between a `VideoCore` abstraction (interface + `media_kit` implementation) and the UI layer. UI consists of an `EmptyState` (when no file loaded) and a `VideoSurface` (when playing), both wrapped in a `DropTarget` that accepts dragged video files. Keyboard handler for Space (play/pause) and arrow keys (seek/volume) wired directly to `VideoCore`.

**Tech Stack:** Flutter 3.x stable, Dart 3.x, `media_kit` (libmpv wrapper), `desktop_drop` (cross-platform drag-drop), Windows x64 target. Tests: `flutter_test` + `mocktail`.

---

## File Structure (Phase 1 deliverables)

```
D:\Repos\MeowWatch\
├── pubspec.yaml                              # Flutter manifest, dependencies
├── analysis_options.yaml                     # Linter config
├── lib\
│   ├── main.dart                             # App entrypoint, initializes media_kit
│   ├── app.dart                              # MaterialApp + theme placeholder
│   ├── core\
│   │   └── video\
│   │       ├── video_core.dart               # Abstract VideoCore interface
│   │       ├── media_kit_video_core.dart     # media_kit-backed implementation
│   │       └── playback_state.dart           # PlaybackState data class
│   └── ui\
│       ├── home_screen.dart                  # Root screen: empty state OR video surface
│       ├── empty_state.dart                  # "Drop a video file" widget
│       ├── video_surface.dart                # Renders video via media_kit + key handlers
│       └── drop_target.dart                  # DropTarget wrapper with file filtering
└── test\
    ├── core\
    │   └── video\
    │       ├── playback_state_test.dart
    │       └── video_core_test.dart          # Tests against a FakeVideoCore + interface contract
    └── ui\
        ├── empty_state_test.dart
        └── drop_target_test.dart
```

Each file has a single clear responsibility. `VideoCore` interface lets UI be tested with a fake; `media_kit_video_core.dart` is exercised manually since libmpv requires a display window.

---

## Task 1: Flutter project scaffold

**Files:**
- Create: `pubspec.yaml`, `lib/main.dart`, `analysis_options.yaml`, plus Flutter-generated platform folders

- [ ] **Step 1: Run `flutter create` in the repo root**

```bash
cd D:/Repos/MeowWatch
flutter create --org com.shanxin --project-name meowwatch --platforms=windows --description "MeowWatch co-watch app" .
```

Expected: Flutter writes pubspec.yaml, lib/main.dart, windows/ folder, etc. Existing `.git/`, `docs/`, `.gitignore`, `.superpowers/` are untouched.

- [ ] **Step 2: Verify default app runs**

```bash
flutter run -d windows
```

Expected: a blank Flutter counter app window opens. Close it.

- [ ] **Step 3: Replace `analysis_options.yaml` with stricter rules**

Content for `analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore

linter:
  rules:
    - prefer_const_constructors
    - prefer_final_locals
    - prefer_final_fields
    - avoid_print
    - always_declare_return_types
    - unawaited_futures
```

- [ ] **Step 4: Run `flutter analyze` to confirm zero issues**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml lib/ test/ windows/ .metadata
git commit -m "chore: scaffold Flutter Windows app"
```

---

## Task 2: Add `media_kit` and `desktop_drop` dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add dependencies to `pubspec.yaml`**

Under `dependencies:` add:

```yaml
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_windows_video: ^1.0.9
  desktop_drop: ^0.4.4
  path: ^1.9.0
```

Under `dev_dependencies:` add:

```yaml
  mocktail: ^1.0.4
```

- [ ] **Step 2: Run `flutter pub get`**

```bash
flutter pub get
```

Expected: dependencies resolve, no errors.

- [ ] **Step 3: Run `flutter analyze`**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: add media_kit, desktop_drop, mocktail"
```

---

## Task 3: Define `PlaybackState` (TDD)

**Files:**
- Create: `lib/core/video/playback_state.dart`
- Test: `test/core/video/playback_state_test.dart`

- [ ] **Step 1: Write failing test**

Content for `test/core/video/playback_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';

void main() {
  group('PlaybackState', () {
    test('defaults to idle, position zero, duration zero', () {
      const state = PlaybackState();
      expect(state.status, PlaybackStatus.idle);
      expect(state.position, Duration.zero);
      expect(state.duration, Duration.zero);
      expect(state.volume, 1.0);
      expect(state.fileName, isNull);
    });

    test('copyWith updates only specified fields', () {
      const initial = PlaybackState();
      final updated = initial.copyWith(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 5),
      );
      expect(updated.status, PlaybackStatus.playing);
      expect(updated.position, const Duration(seconds: 5));
      expect(updated.duration, Duration.zero);
      expect(updated.volume, 1.0);
    });

    test('equal states are equal', () {
      const a = PlaybackState(status: PlaybackStatus.playing);
      const b = PlaybackState(status: PlaybackStatus.playing);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
flutter test test/core/video/playback_state_test.dart
```

Expected: FAIL — `playback_state.dart` does not exist.

- [ ] **Step 3: Implement minimal `PlaybackState`**

Content for `lib/core/video/playback_state.dart`:

```dart
import 'package:flutter/foundation.dart';

enum PlaybackStatus { idle, loading, playing, paused, ended, error }

@immutable
class PlaybackState {
  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.fileName,
    this.errorMessage,
  });

  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double volume;
  final String? fileName;
  final String? errorMessage;

  PlaybackState copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    double? volume,
    String? fileName,
    String? errorMessage,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      fileName: fileName ?? this.fileName,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackState &&
        other.status == status &&
        other.position == position &&
        other.duration == duration &&
        other.volume == volume &&
        other.fileName == fileName &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        status,
        position,
        duration,
        volume,
        fileName,
        errorMessage,
      );
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
flutter test test/core/video/playback_state_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/video/playback_state.dart test/core/video/playback_state_test.dart
git commit -m "feat(video): add PlaybackState data class"
```

---

## Task 4: Define `VideoCore` interface + `FakeVideoCore` (TDD)

**Files:**
- Create: `lib/core/video/video_core.dart`
- Test: `test/core/video/video_core_test.dart`

- [ ] **Step 1: Write failing test (contract tests against FakeVideoCore)**

Content for `test/core/video/video_core_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

class FakeVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      fileName: filePath,
      status: PlaybackStatus.paused,
      duration: const Duration(minutes: 30),
      position: Duration.zero,
    ));
  }

  @override
  Future<void> play() async {
    emit(state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    emit(state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    emit(state.copyWith(volume: volume));
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeVideoCore core;

  setUp(() {
    core = FakeVideoCore();
  });

  tearDown(() async {
    await core.dispose();
  });

  test('initial state is idle', () {
    expect(core.state.status, PlaybackStatus.idle);
  });

  test('load() transitions to paused with file name', () async {
    await core.load('C:\\videos\\demo.mkv');
    expect(core.state.status, PlaybackStatus.paused);
    expect(core.state.fileName, 'C:\\videos\\demo.mkv');
  });

  test('play() and pause() update status', () async {
    await core.load('test.mkv');
    await core.play();
    expect(core.state.status, PlaybackStatus.playing);
    await core.pause();
    expect(core.state.status, PlaybackStatus.paused);
  });

  test('state stream emits on changes', () async {
    final states = <PlaybackState>[];
    final sub = core.stateStream.listen(states.add);
    await core.load('test.mkv');
    await core.play();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(states.length, greaterThanOrEqualTo(2));
    expect(states.last.status, PlaybackStatus.playing);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
flutter test test/core/video/video_core_test.dart
```

Expected: FAIL — `video_core.dart` does not exist.

- [ ] **Step 3: Implement `VideoCore` abstract class**

Content for `lib/core/video/video_core.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';

import 'playback_state.dart';

/// Abstract interface for video playback. Implementations may wrap libmpv,
/// a fake for tests, or any other backend.
abstract class VideoCore {
  VideoCore() : _state = const PlaybackState();

  PlaybackState _state;
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  PlaybackState get state => _state;
  Stream<PlaybackState> get stateStream => _controller.stream;

  /// Emit a new state. Implementations call this from their backend listeners.
  @protected
  void emit(PlaybackState next) {
    _state = next;
    _controller.add(next);
  }

  Future<void> load(String filePath);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();

  Future<void> togglePlay() async {
    if (state.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }
}
```

`package:meta` is in the Flutter SDK transitively — no pubspec change needed.

- [ ] **Step 4: Run tests, verify pass**

```bash
flutter test test/core/video/video_core_test.dart
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/video/video_core.dart test/core/video/video_core_test.dart
git commit -m "feat(video): add VideoCore abstract interface"
```

---

## Task 5: Implement `MediaKitVideoCore`

Real playback can't be reliably unit-tested (libmpv needs a display). Implement it, exercise it via manual E2E in Task 9.

**Files:**
- Create: `lib/core/video/media_kit_video_core.dart`

- [ ] **Step 1: Write implementation**

Content for `lib/core/video/media_kit_video_core.dart`:

```dart
import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'playback_state.dart';
import 'video_core.dart';

class MediaKitVideoCore extends VideoCore {
  MediaKitVideoCore() : _player = Player() {
    _wireListeners();
  }

  final Player _player;
  late final List<StreamSubscription<dynamic>> _subs;

  Player get player => _player;

  void _wireListeners() {
    _subs = [
      _player.stream.playing.listen((playing) {
        emit(state.copyWith(
          status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        ));
      }),
      _player.stream.position.listen((pos) {
        emit(state.copyWith(position: pos));
      }),
      _player.stream.duration.listen((dur) {
        emit(state.copyWith(duration: dur));
      }),
      _player.stream.volume.listen((vol) {
        emit(state.copyWith(volume: vol / 100.0));
      }),
      _player.stream.completed.listen((done) {
        if (done) emit(state.copyWith(status: PlaybackStatus.ended));
      }),
      _player.stream.error.listen((err) {
        emit(state.copyWith(
          status: PlaybackStatus.error,
          errorMessage: err.toString(),
        ));
      }),
    ];
  }

  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: p.basename(filePath),
      position: Duration.zero,
      duration: Duration.zero,
      errorMessage: null,
    ));
    await _player.open(Media(filePath), play: false);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume((volume.clamp(0.0, 1.0)) * 100.0);

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }
}
```

- [ ] **Step 2: Run `flutter analyze`**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/video/media_kit_video_core.dart
git commit -m "feat(video): implement MediaKitVideoCore over libmpv"
```

---

## Task 6: Build `EmptyState` widget (TDD)

**Files:**
- Create: `lib/ui/empty_state.dart`
- Test: `test/ui/empty_state_test.dart`

- [ ] **Step 1: Write failing widget test**

Content for `test/ui/empty_state_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/empty_state.dart';

void main() {
  testWidgets('shows prompt text and Browse button', (tester) async {
    var browseCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmptyState(onBrowse: () => browseCalled = true),
      ),
    ));

    expect(find.textContaining('Drop a video'), findsOneWidget);
    expect(find.text('Browse…'), findsOneWidget);

    await tester.tap(find.text('Browse…'));
    await tester.pump();
    expect(browseCalled, isTrue);
  });
}
```

- [ ] **Step 2: Run test, verify fail**

```bash
flutter test test/ui/empty_state_test.dart
```

Expected: FAIL — `empty_state.dart` does not exist.

- [ ] **Step 3: Implement widget**

Content for `lib/ui/empty_state.dart`:

```dart
import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({required this.onBrowse, super.key});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1410),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_outlined,
                size: 64, color: Color(0xFFD4A574)),
            const SizedBox(height: 16),
            const Text(
              'Drop a video file to start',
              style: TextStyle(color: Color(0xFFF5E6D3), fontSize: 18),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD4A574),
                side: const BorderSide(color: Color(0xFFD4A574)),
              ),
              onPressed: onBrowse,
              child: const Text('Browse…'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test, verify pass**

```bash
flutter test test/ui/empty_state_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/empty_state.dart test/ui/empty_state_test.dart
git commit -m "feat(ui): add EmptyState widget"
```

---

## Task 7: Build `DropTarget` wrapper (TDD)

**Files:**
- Create: `lib/ui/drop_target.dart`
- Test: `test/ui/drop_target_test.dart`

`desktop_drop` exposes a `DropTarget` widget; we wrap it to filter video extensions and surface a clean `onFileDropped(path)` callback.

- [ ] **Step 1: Write failing test (only tests the path-filtering logic, not the native drag)**

Content for `test/ui/drop_target_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/drop_target.dart';

void main() {
  group('isVideoFile', () {
    test('accepts common video extensions', () {
      expect(isVideoFile('foo.mkv'), isTrue);
      expect(isVideoFile('foo.MP4'), isTrue);
      expect(isVideoFile('C:\\path\\foo.avi'), isTrue);
      expect(isVideoFile('foo.webm'), isTrue);
      expect(isVideoFile('foo.mov'), isTrue);
    });

    test('rejects non-video files', () {
      expect(isVideoFile('foo.txt'), isFalse);
      expect(isVideoFile('foo.jpg'), isFalse);
      expect(isVideoFile('foo'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test, verify fail**

```bash
flutter test test/ui/drop_target_test.dart
```

Expected: FAIL — `drop_target.dart` does not exist.

- [ ] **Step 3: Implement `DropTarget` wrapper + `isVideoFile`**

Content for `lib/ui/drop_target.dart`:

```dart
import 'package:desktop_drop/desktop_drop.dart' as dd;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

const _videoExtensions = <String>{
  '.mkv', '.mp4', '.avi', '.webm', '.mov', '.m4v', '.flv', '.ts', '.mpg', '.mpeg',
};

bool isVideoFile(String path) {
  return _videoExtensions.contains(p.extension(path).toLowerCase());
}

class VideoDropTarget extends StatelessWidget {
  const VideoDropTarget({
    required this.child,
    required this.onFileDropped,
    super.key,
  });

  final Widget child;
  final void Function(String path) onFileDropped;

  @override
  Widget build(BuildContext context) {
    return dd.DropTarget(
      onDragDone: (detail) {
        for (final file in detail.files) {
          if (isVideoFile(file.path)) {
            onFileDropped(file.path);
            return;
          }
        }
      },
      child: child,
    );
  }
}
```

- [ ] **Step 4: Run test, verify pass**

```bash
flutter test test/ui/drop_target_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/drop_target.dart test/ui/drop_target_test.dart
git commit -m "feat(ui): add VideoDropTarget with extension filtering"
```

---

## Task 8: Build `VideoSurface` widget + keyboard handlers

**Files:**
- Create: `lib/ui/video_surface.dart`

No unit test — widget renders an actual video texture which requires libmpv display context. Will be exercised in manual E2E.

- [ ] **Step 1: Write `VideoSurface`**

Content for `lib/ui/video_surface.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';

class VideoSurface extends StatefulWidget {
  const VideoSurface({required this.core, super.key});

  final MediaKitVideoCore core;

  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<VideoSurface> {
  late final VideoController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = VideoController(widget.core.player);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final core = widget.core;
    final s = core.state;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      core.togglePlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      core.seek(s.position + const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      core.seek(s.position - const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      core.setVolume((s.volume + 0.05).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      core.setVolume((s.volume - 0.05).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      autofocus: true,
      child: Container(
        color: Colors.black,
        child: Video(controller: _controller),
      ),
    );
  }
}
```

- [ ] **Step 2: Run `flutter analyze`**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/ui/video_surface.dart
git commit -m "feat(ui): add VideoSurface with keyboard controls"
```

---

## Task 9: Compose `HomeScreen`

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/ui/home_screen.dart`

- [ ] **Step 1: Add `file_selector` to `pubspec.yaml`**

Under `dependencies:` add `file_selector: ^1.0.3`. Then:

```bash
flutter pub get
```

Expected: dependency resolves cleanly.

- [ ] **Step 2: Write `HomeScreen`**

Content for `lib/ui/home_screen.dart`:

```dart
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'video_surface.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MediaKitVideoCore _core;

  @override
  void initState() {
    super.initState();
    _core = MediaKitVideoCore();
  }

  @override
  void dispose() {
    unawaited(_core.dispose());
    super.dispose();
  }

  Future<void> _loadAndPlay(String path) async {
    await _core.load(path);
    await _core.play();
  }

  Future<void> _browse() async {
    const typeGroup = XTypeGroup(
      label: 'Video',
      extensions: ['mkv', 'mp4', 'avi', 'webm', 'mov', 'm4v'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await _loadAndPlay(file.path);
    }
  }

  void _handleDropped(String path) {
    unawaited(_loadAndPlay(path));
  }

  @override
  Widget build(BuildContext context) {
    return VideoDropTarget(
      onFileDropped: _handleDropped,
      child: StreamBuilder<PlaybackState>(
        stream: _core.stateStream,
        initialData: _core.state,
        builder: (context, snapshot) {
          final state = snapshot.data!;
          if (state.fileName == null) {
            return EmptyState(onBrowse: _browse);
          }
          return VideoSurface(core: _core);
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Run `flutter analyze`**

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/ui/home_screen.dart pubspec.yaml pubspec.lock
git commit -m "feat(ui): compose HomeScreen with drop target and player"
```

---

## Task 10: Wire `main.dart` + initialize media_kit

**Files:**
- Modify: `lib/main.dart`, create `lib/app.dart`

- [ ] **Step 1: Replace generated `lib/main.dart`**

Content for `lib/main.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MeowWatchApp());
}
```

- [ ] **Step 2: Create `lib/app.dart`**

Content for `lib/app.dart`:

```dart
import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

class MeowWatchApp extends StatelessWidget {
  const MeowWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeowWatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4A574),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
```

- [ ] **Step 3: Run `flutter analyze`**

Expected: `No issues found!`

- [ ] **Step 4: Run full test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/app.dart
git commit -m "feat: wire main entrypoint and MaterialApp"
```

---

## Task 11: Manual end-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Run the app**

```bash
flutter run -d windows
```

Expected: a dark window opens with "Drop a video file to start" + Browse… button.

- [ ] **Step 2: Test drag-and-drop**

Drag any `.mkv` or `.mp4` file from Explorer onto the window.

Expected: video starts playing.

- [ ] **Step 3: Test Browse button**

Restart the app. Click "Browse…", pick a video file.

Expected: video starts playing.

- [ ] **Step 4: Test keyboard controls**

While video plays, press:
- `Space` → pauses, then resumes
- `→` → seeks forward 5s (visible position jump)
- `←` → seeks back 5s
- `↑` / `↓` → no visible change but Windows volume mixer should show MeowWatch volume changing

- [ ] **Step 5: Test unsupported file**

Drag a `.txt` file onto the window.

Expected: nothing happens (no load attempt, no crash).

- [ ] **Step 6: Close app cleanly**

Close window. Process should exit (check Task Manager — no orphaned `meowwatch.exe`).

- [ ] **Step 7: If any step failed, file an issue**

Note specifics in `docs/phase-1-issues.md`. Otherwise move on.

- [ ] **Step 8: Tag the milestone**

```bash
git tag phase-1-complete -m "Phase 1: drag-drop video playback works"
```

---

## Phase 1 done

At this point: a polished-feeling Flutter window plays any local video via drag-drop or browse, with keyboard control. No chat, no sync, no theming. Next plan: Phase 2 — Sync core (Syncplay protocol).
