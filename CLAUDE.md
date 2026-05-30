# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

MeowWatch is a Flutter **desktop** (Windows-first) co-watch app: load a local video, connect to a public Syncplay room, stay in sync with a friend, and chat over a floating overlay. Built in six phases (see `docs/ROADMAP.md`); Phases 1–2 shipped, Phase 3 (chat) in progress.

## Gotchas (read first — these have bitten us)

- **Flutter is installed via Puro and is NOT on PATH.** Always use the absolute binary:
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`. Plain `flutter` will fail.
- **Manual testing must use the Release build, not Debug.** A stale/Debug `meowwatch.exe` has caused "the fix isn't showing up" confusion. Verify the artifact you're launching is `build/windows/x64/runner/Release/meowwatch.exe`.
- **Two instances on one PC need software video decoding (already forced).** Default mpv hardware decode lets two instances fight over the single HW decoder session — whichever opens its file *second* freezes at frame 0, and the sync layer then drags the healthy client backward forever (rewind-to-stay-together chasing the frozen peer). `MediaKitVideoCore._configureDecoding()` sets `hwdec=no` so each instance decodes independently. Don't "optimize" this back to HW decode — it breaks two-instance manual testing and is harmless on real two-machine use (one decoder per machine). This was the root cause of a long "can't play in a room" hunt; the diagnostic was an `hwdec` issue, not the sync/auto-pause code.
- **Kill running instances before `flutter build windows`.** A running `meowwatch.exe` holds a file lock; the linker can leave the **old** binary in place while the build still reports success. `Stop-Process -Name meowwatch -Force` first.
- **The `.exe` mtime is a red herring for Dart changes.** `meowwatch.exe` is the C++ runner and only changes when native code changes. Dart edits compile into `build/windows/x64/runner/Release/data/app.so` — check *that* timestamp to confirm a rebuild picked up Dart changes.
- **Stream emissions are async (microtask).** In tests, after pushing into a stream/calling a method that emits, `await Future<void>.delayed(Duration.zero)` before asserting on the result, or the assert runs before the listener fires.
- **Golden tests must be regenerated when their widget changes.** Editing a chat widget changes `test/ui/chat/goldens/*.png`; a plain `flutter test` then fails on mismatch. Re-run that test file with `--update-goldens` and visually inspect the PNG before committing.
- **`prefer_initializing_formals` false-positive:** private fields initialized from named params can't use initializing formals (named params can't start with `_`). Suppress per-file with `// ignore_for_file: prefer_initializing_formals` rather than restructuring.

## Commands

```bash
FLUTTER=C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat

$FLUTTER analyze                                   # lint/type check — keep at "No issues found!"
$FLUTTER test                                      # full suite
$FLUTTER test test/ui/chat/chat_bubble_test.dart   # single file
$FLUTTER test path/to/file_test.dart -p "name"     # single test by name (-p / --plain-name)
$FLUTTER test test/ui/chat/chat_overlay_golden_test.dart --update-goldens  # regenerate goldens
$FLUTTER build windows                             # Release exe (kill running instances first)
$FLUTTER run -d windows                            # debug run
```

## Architecture

**Commands-in / streams-out.** The two core subsystems — video and sync — expose the same shape: an abstract interface with imperative methods for input and broadcast `Stream`s for output. UI never reaches into internals; it calls methods and listens to streams. This makes both swappable with fakes in tests.

- `core/video/` — `VideoCore` (abstract) → `MediaKitVideoCore` (libmpv via `media_kit`). Emits immutable `PlaybackState`.
- `core/sync/` — `SyncCore` (abstract, owns the broadcast controllers + `@protected emit*` + `@mustCallSuper dispose`) → `SyncplayClient` (custom Dart Syncplay client: TCP + startTLS, Hello handshake, State heartbeat, `ignoringOnTheFly`/`setBy` convergence). Data types in `peer_state.dart`; wire framing/encoders in `sync_messages.dart` / `syncplay_constants.dart`.
- `core/chat/` — `ChatStore` subscribes to `SyncCore.chat`, stamps each message's local arrival time, and republishes an immutable list.
- `core/update/` — `UpdateService` checks a Cloudflare R2 bucket (`{updateBaseUrl}/releases/latest.json`) for new versions, downloads a zip, extracts it, then launches a PowerShell updater script that swaps the files and restarts. Version constant in `app_version.dart`.
- `core/app_version.dart` — single source of truth for `appVersion` (keep in sync with `pubspec.yaml`) and `updateBaseUrl`.

**Pure logic is split out from widgets** so it can be unit-tested headless (no widget pump):
- `sync_follow.dart` — `decideFollow(...)`: should we follow a peer's state change?
- `chat_corner.dart` — `computeSnap(...)`: where does a dragged card land (corner vs. edge-collapse)?
- `chat_overlay_layout.dart` — `ChatOverlayLayout` immutable state (`toggle`/`applySnap`).

**Glue:** `PlaybackSyncBridge` wires `VideoCore` ⇄ `SyncCore` (local playback → outgoing State; incoming peer state → local seek/pause via `decideFollow`). `HomeScreen` owns the instances, subscribes to all streams, and composes the UI Stack: video surface + auto-hiding controls + sync-hint banner + chat overlay.

**Chat data flow:** sending delegates to `SyncCore.sendChat`; the server echoes the sender's own message back to the whole room, so messages land via the normal receive path. There is **no optimistic local insert** — the stream is the single source of truth.

**Immutability:** state objects (`PlaybackState`, `ChatMessage`, `ChatOverlayLayout`, etc.) are `@immutable` with `copyWith`; never mutate in place.

**Theme (Phase 3, hardcoded "Cozy"; theming arrives in Phase 5):** warm dark `0xFF1A1410`, card fill `0xF2241B14`, amber accent `0xFFD4A574`, cream text `0xFFF5E6D3`, dim text `0x99F5E6D3`, border `0x55D4A574`.

## Workflow

TDD (RED → GREEN → REFACTOR), small commits at verified milestones. Conventional-commit messages (`feat:`, `fix:`, …). Don't tag a phase complete until the user confirms a manual two-instance test passes. Specs live in `docs/superpowers/specs/`, per-phase plans in `docs/superpowers/plans/`.

## Maintaining this file

Keep this file current. When you discover a new sharp edge (a build quirk, a test trap, a non-obvious convention) or make a structural change to the architecture above, update the relevant section in the same change — don't let it drift. Prefer fixing/expanding an existing bullet over appending duplicates.
