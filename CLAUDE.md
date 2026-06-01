# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

MeowWatch is a Flutter **desktop** (Windows-first) co-watch app: load a local video, connect to a public Syncplay room, stay in sync with a friend, and chat over a floating overlay. Built in six phases (see `docs/ROADMAP.md`); Phases 1–2 shipped, Phase 3 (chat) in progress.

## Gotchas (read first — these have bitten us)

- **Flutter is installed via Puro and is NOT on PATH.** Always use the absolute binary:
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`. Plain `flutter` will fail.
- **Manual testing must use the Release build, not Debug.** A stale/Debug `meowwatch.exe` has caused "the fix isn't showing up" confusion. Verify the artifact you're launching is `build/windows/x64/runner/Release/meowwatch.exe`.
- **Dead-connection detection can't rely on socket `onDone`/`onError`.** A half-open TCP (server vanishes, NAT idle-eviction, Wi-Fi blip — peer never sends FIN/RST) leaves the socket "open" on our side: writes succeed into a black hole, no callback ever fires, and the app would sit on "connected" forever while chats go nowhere. `SyncplayClient` runs a `ConnectionWatchdog` that `bump()`s on every incoming byte and trips after `livenessTimeout` (12s ≫ the ~1s State heartbeat) → emits `reconnecting` → backed-off auto-reconnect. Don't remove it assuming the socket callbacks cover drops — they only cover *clean* closes. Relatedly, `disconnect()` uses `_socket.destroy()` not `close()`: `close()` awaits a flush that a half-open socket can never complete, which is what once wedged the "Leave room" button.
- **Two instances on one PC need software video decoding (already forced).** Default mpv hardware decode lets two instances fight over the single HW decoder session — whichever opens its file *second* freezes at frame 0, and the sync layer then drags the healthy client backward forever (rewind-to-stay-together chasing the frozen peer). `MediaKitVideoCore._configureDecoding()` sets `hwdec=no` so each instance decodes independently. Don't "optimize" this back to HW decode — it breaks two-instance manual testing and is harmless on real two-machine use (one decoder per machine). This was the root cause of a long "can't play in a room" hunt; the diagnostic was an `hwdec` issue, not the sync/auto-pause code.
- **Kill running instances before `flutter build windows`.** A running `meowwatch.exe` holds a file lock; the linker can leave the **old** binary in place while the build still reports success. `Stop-Process -Name meowwatch -Force` first.
- **The `.exe` mtime is a red herring for Dart changes.** `meowwatch.exe` is the C++ runner and only changes when native code changes. Dart edits compile into `build/windows/x64/runner/Release/data/app.so` — check *that* timestamp to confirm a rebuild picked up Dart changes.
- **Stream emissions are async (microtask).** In tests, after pushing into a stream/calling a method that emits, `await Future<void>.delayed(Duration.zero)` before asserting on the result, or the assert runs before the listener fires.
- **Golden tests must be regenerated when their widget changes.** Editing a chat widget changes `test/ui/chat/goldens/*.png`; a plain `flutter test` then fails on mismatch. Re-run that test file with `--update-goldens` and visually inspect the PNG before committing.
- **`prefer_initializing_formals` false-positive:** private fields initialized from named params can't use initializing formals (named params can't start with `_`). Suppress per-file with `// ignore_for_file: prefer_initializing_formals` rather than restructuring.
- **The auto-updater must be launched OUTSIDE the app's job object, or it dies on `exit(0)`.** The app runs inside a Windows job object; a detached child we spawn ourselves stays in that job, so the job's kill-on-close terminates it the instant the app exits — before it runs a single line. Symptom: clicking Install closes the app, nothing happens, version unchanged, no `updater.log` written. `applyUpdate` routes through `cmd /c start "" powershell …` (see `buildUpdaterLaunch`) so PowerShell is re-parented outside our process tree. Do NOT "simplify" this back to `Process.start('powershell', …)`. Verified by repro: detached powershell + immediate `exit(0)` ⇒ child killed; via `cmd start` ⇒ survives.
- **`gh` CLI authentication failure:** AI sandbox environment injects invalid `GITHUB_TOKEN` environment variable. `gh` tool prioritize environment variable and ignore valid credentials in user system keyring. Always clear `GITHUB_TOKEN` before run `gh` command (e.g., `powershell -Command '$env:GITHUB_TOKEN=$null; gh ...'`).


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

**Versioning (every behavior-changing PR):** bump the version in lockstep across `pubspec.yaml` (`version:`), `lib/core/app_version.dart` (`appVersion`), and `CHANGELOG.md` (new top `## [<version>] - <date>` entry).

Semver is `MAJOR.MINOR.PATCH` — **three separate digit slots**, each is the digit *in that position*, NOT "the next number overall":
- `MAJOR` = **1st** digit — big/breaking change. Bumping it resets MINOR and PATCH to 0 (`0.2.3 → 1.0.0`).
- `MINOR` = **2nd** digit — new feature. Bumping it resets PATCH to 0 (`0.1.3 → 0.2.0`, **not** `0.1.4`).
- `PATCH` = **3rd** digit — bug fix / small tweak (`0.1.3 → 0.1.4`).

So a `feat:` PR is a MINOR bump = 2nd digit + reset 3rd to 0. A `fix:` PR is a PATCH bump = 3rd digit. Common mistake: bumping the 3rd digit and calling it "minor" — the 3rd digit is PATCH.

Keep the `-alpha` suffix until we move off alpha. CI parses `CHANGELOG.md` → `releases/changelog.json` on R2, which the in-app updater reads — so the three files drifting out of sync breaks the updater's "what changed" view.

**Release flow (the user finds this sequence helpful — follow it for every release):**
1. Land work on a feature/fix branch → open a PR to `main`. Don't push `v*` tags from the branch.
2. Wait for the automatic **Copilot review**, then run the `address-pr-review` skill: fix or reject each comment with a real reason, reply, resolve the threads, push.
3. If a manual test is warranted (visible behavior change), get the user's confirmation first; pure edge-case/defensive fixes with unit coverage don't need one — say so.
4. Wait for **CI green** (the `Build / Analyze & Test` check — the PR gate). The full `Windows x64` build does **not** run on PRs; it runs only on the tag push. Then **merge** the PR to `main` (merge commit).
5. `git checkout main && git pull` → **tag** `v<version>` on the merge commit → `git push origin v<version>`. The tag fires the build + release jobs (build → R2 upload + `changelog.json`). Since this is the *first* clean-room Windows build for the change, watch it — a build-only breakage surfaces here, not at PR time.
6. Wait for the release run green, then **verify R2**: `curl …/releases/latest.json` (version matches) and `…/releases/changelog.json` (array includes the new version).
7. **Wrap up** once R2 is verified — run the `call-it-a-day` skill (or do it by hand): `git checkout main && git pull` so main is the merge+tag commit, delete the merged branch (local + remote), prune the feature worktree under `.claude/worktrees/`, remove session scratch files, and stop any leftover `meowwatch.exe` dev/test instances. End on a clean `git status` on `main`. Don't start this until after the merge, tag, and R2 verification — the worktree is still needed for PR iteration before then.

**Auto-update has a one-version lag:** the running app applies updates with *its own* (old) `buildUpdaterScript`, so a fix to the updater only takes effect for updates *from* the fixed version onward. After shipping an updater fix, that one hop must be installed **manually** (download the R2 zip, replace the install folder); auto-update works from the fixed version on. (The pre-0.1.3 updater used `Copy-Item -Recurse`, which nested `data\data\` and never replaced `app.so` — so 0.1.2→0.1.3 needs a manual install.)

## Maintaining this file

Keep this file current. When you discover a new sharp edge (a build quirk, a test trap, a non-obvious convention) or make a structural change to the architecture above, update the relevant section in the same change — don't let it drift. Prefer fixing/expanding an existing bullet over appending duplicates.
