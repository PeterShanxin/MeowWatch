# Agent Guide

This file provides shared guidance for AI coding agents working in this repository.

Root tool entrypoints (`AGENTS.md`, `CLAUDE.md`) intentionally stay small and point here. Keep general repo guidance in this file; use root entrypoints only for tool-specific overrides.

MeowWatch is a Flutter **desktop** (Windows-first) co-watch app: load a local video, connect to a public Syncplay room, stay in sync with a friend, and chat over a floating overlay. Built in six phases (see `docs/ROADMAP.md`); Phases 1–2 shipped, Phase 3 (chat) in progress.

## Gotchas (read first — these have bitten us)

- **Flutter is installed via Puro and is NOT on PATH.** Always use the absolute binary:
  `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`. Plain `flutter` will fail.
- **Manual testing must use the Release build, not Debug.** A stale/Debug `meowwatch.exe` has caused "the fix isn't showing up" confusion. Verify the artifact you're launching is `build/windows/x64/runner/Release/meowwatch.exe`.
- **Dead-connection detection can't rely on socket `onDone`/`onError`.** A half-open TCP (server vanishes, NAT idle-eviction, Wi-Fi blip — peer never sends FIN/RST) leaves the socket "open" on our side: writes succeed into a black hole, no callback ever fires, and the app would sit on "connected" forever while chats go nowhere. `SyncplayClient` runs a `ConnectionWatchdog` that `bump()`s on every incoming byte and trips after `livenessTimeout` (12s ≫ the ~1s State heartbeat) → emits `reconnecting` → backed-off auto-reconnect. Don't remove it assuming the socket callbacks cover drops — they only cover *clean* closes. Relatedly, `disconnect()` uses `_socket.destroy()` not `close()`: `close()` awaits a flush that a half-open socket can never complete, which is what once wedged the "Leave room" button.
- **HW decode is the default; two instances on one PC need it forced OFF via env var.** `MediaKitVideoCore._configureDecoding()` defaults to hardware decode: `hwdec=d3d11va` on Windows (the **zero-copy** D3D11VA path — keeps decoded frames in GPU memory for media_kit's ANGLE texture path, avoiding the GPU→RAM→GPU copy-back `auto-safe` might pick; mpv auto-falls-back to software inside the decoder if d3d11va can't init), `hwdec=auto-safe` on every other platform (hardware decode on mpv's whitelist with automatic software fallback). Both are a big CPU/battery/heat win on Snapdragon X / Adreno. The catch: two app instances on one PC fight over the single HW decoder session — whichever opens its file *second* freezes at frame 0, and the sync layer then drags the healthy client backward forever (rewind-to-stay-together chasing the frozen peer). So for **two-instance-on-one-PC local testing**, set `MEOWWATCH_FORCE_SW_DECODE=1` before launching (PowerShell: `$env:MEOWWATCH_FORCE_SW_DECODE='1'`) — that flips back to `hwdec=no` and each instance decodes independently. Real two-machine use has one decoder per machine and needs nothing. The decision is pure logic in `video_decode_config.dart` (`resolveHwdec({forceSoftware, isWindows})` / `forceSoftwareDecodeFromEnv`), unit-tested in `test/core/video/video_decode_config_test.dart`. This HW-vs-SW split was once the root cause of a long "can't play in a room" hunt — the diagnostic was an `hwdec` contention issue, not the sync/auto-pause code.
- **`video-sync=display-resample` is always set; revert via env var if needed.** `_configureDecoding()` also sets `video-sync=display-resample` — this locks frame presentation to the monitor refresh rate (resampling audio slightly to maintain A/V lock) for smoother motion and fewer dropped frames. To revert to mpv's default audio-clock mode (e.g. for VRR/multi-monitor setups or sync debugging), set `MEOWWATCH_FORCE_AUDIO_SYNC=1` before launching. Pure logic in `video_decode_config.dart` (`resolveVideoSync` / `forceAudioSyncFromEnv`), unit-tested alongside the hwdec config. (#74)
- **Never emit a `Positioned` unless it's a *direct* child of a `Stack` — a misused one paints the whole screen translucent-white in release (#50).** `ChatOverlay` is mounted under `AnimatedOpacity > IgnorePointer` (see `HomeScreen`), **not** a Stack. Its drag/resize render path used to `return Positioned.fill(...)`; `Positioned` is a `ParentDataWidget` that requires a `RenderStack` parent, so that was a misuse. In **debug** it asserts; in **release** (asserts stripped) the bad parent-data slipped through and the engine composited the whole window wrong → a continuous translucent **pale-white wash over the entire screen for the whole drag**, on every theme, with or without a video. Fix: the overlay fills its own box with `SizedBox.expand`; the only `Positioned` lives inside the *inner* `Stack` that actually holds the card. Diagnosis traps that wasted hours here: the flash is **release-only** (debug renders it fine — don't conclude "fixed" from a debug run), it's **not** Impeller (repros with `--no-enable-impeller`), and **nothing in `lib/` is actually white** (all themes are dark) so it's never a widget colour. The old `chat_overlay_test.dart` missed it because its host wrapped the overlay in a `Stack`, which makes the misused `Positioned` legal — the regression guard in `chat_overlay_repaint_test.dart` mounts it under `IgnorePointer` like the real app. (#42's "hide the drop-zone hints during resize" was a red herring that never touched the real cause.) `ChatOverlay` also wraps its output in a `RepaintBoundary` — a separate repaint-isolation nicety, not the white-flash fix.
- **Kill running instances before `flutter build windows`.** A running `meowwatch.exe` holds a file lock; the linker can leave the **old** binary in place while the build still reports success. `Stop-Process -Name meowwatch -Force` first.
- **The `.exe` mtime is a red herring for Dart changes.** `meowwatch.exe` is the C++ runner and only changes when native code changes. Dart edits compile into `build/windows/x64/runner/Release/data/app.so` — check *that* timestamp to confirm a rebuild picked up Dart changes.
- **Stream emissions are async (microtask).** In tests, after pushing into a stream/calling a method that emits, `await Future<void>.delayed(Duration.zero)` before asserting on the result, or the assert runs before the listener fires.
- **Golden tests must be regenerated when their widget changes.** Editing a chat widget changes `test/ui/chat/goldens/*.png`; a plain `flutter test` then fails on mismatch. Re-run that test file with `--update-goldens` and visually inspect the PNG before committing.
- **`prefer_initializing_formals` false-positive:** private fields initialized from named params can't use initializing formals (named params can't start with `_`). Suppress per-file with `// ignore_for_file: prefer_initializing_formals` rather than restructuring.
- **Release builds must NOT `AttachConsole(ATTACH_PARENT_PROCESS)` — it adopts the updater's PowerShell console (#97).** The auto-updater relaunches us from inside its PowerShell process, so on startup the *parent* console is PowerShell's. The stock Flutter runner (`windows/runner/main.cpp`) calls `AttachConsole(ATTACH_PARENT_PROCESS)` to show `flutter run` logs — but in a shipped build that means the relaunched app **adopts PowerShell's console and keeps it alive after PowerShell exits**, leaving an empty console window lingering for the whole app session, whose **X button sends `CTRL_CLOSE_EVENT` straight to the app and kills it**. Fix: the `AttachConsole`/`CreateAndAttachConsole` block is guarded behind `#ifndef NDEBUG`, so it runs only in debug (`flutter run` logs preserved) and Release never adopts a parent console. Don't remove the guard to "get logs in release" — Release has no useful stdout and you'll resurrect the lingering-window + kill-switch bug. Pairs with `bringToFront()` in `lib/main.dart`: an updater-relaunched window also can't beat Windows' foreground-lock (it's launched by a background process), so it lands behind other windows; the `alwaysOnTop` true→false bump (`HWND_TOPMOST`, needs no foreground rights) raises it without pinning. Both are app-side, so they take effect on the *next* update, not the hop onto the fixed version's predecessor.
- **The auto-updater must be launched OUTSIDE the app's job object, or it dies on `exit(0)`.** The app runs inside a Windows job object; a detached child we spawn ourselves stays in that job, so the job's kill-on-close terminates it the instant the app exits — before it runs a single line. Symptom: clicking Install closes the app, nothing happens, version unchanged, no `updater.log` written. `applyUpdate` routes through `cmd /c start "" powershell …` (see `buildUpdaterLaunch`) so PowerShell is re-parented outside our process tree. Do NOT "simplify" this back to `Process.start('powershell', …)`. Verified by repro: detached powershell + immediate `exit(0)` ⇒ child killed; via `cmd start` ⇒ survives.
- **`gh` CLI authentication failure:** AI sandbox environment injects invalid `GITHUB_TOKEN` environment variable. `gh` tool prioritize environment variable and ignore valid credentials in user system keyring. Always clear `GITHUB_TOKEN` before run `gh` command (e.g., `powershell -Command '$env:GITHUB_TOKEN=$null; gh ...'`).


## Commands

```bash
FLUTTER=C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat

$FLUTTER analyze                                   # lint/type check — keep at "No issues found!"
$FLUTTER test                                      # full suite
$FLUTTER test test/ui/chat/chat_bubble_test.dart   # single file
$FLUTTER test path/to/file_test.dart --plain-name "name"  # single test by name (--plain-name)
$FLUTTER test test/ui/chat/chat_overlay_golden_test.dart --update-goldens  # regenerate goldens
$FLUTTER build windows                             # Release exe (kill running instances first)
$FLUTTER run -d windows                            # debug run
```

### When hosted Actions is unavailable: the local gate

Hosted Actions is normally funded — the 3,000 included Pro minutes plus a small monthly **Actions budget** (a few dollars, with "stop usage when budget is reached" **on**). Because the self-hosted runner keeps the expensive Windows builds off the meter, hosted overage is tiny (only the 1× Ubuntu `check`/`release` jobs), so runs work in normal operation.

Hosted Actions becomes **unavailable** only if both the included minutes *and* the budget cap are spent (or the budget is removed). When that happens hosted runs fail/stop instantly — **don't wait on or re-trigger the hosted check.** Use local verification on this dev PC as the substitute PR gate:

```bash
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze --no-pub
C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test --no-pub --concurrency=1 --reporter compact
```

Then build Release and do the manual test (see the Gotchas: kill build-path `meowwatch.exe` first, verify the rebuild via `build/windows/x64/runner/Release/data/app.so` mtime, launch the Release exe). Merge only after local analyze + test + build are green and the manual test passes.

## Continuous integration (CI)

The repo is **private**, so GitHub-hosted Actions minutes are metered (GitHub Pro = 3,000 min/month, resetting on the 1st). Minutes are charged by a per-OS multiplier: **Linux 1×, Windows 2×, macOS 10×**. Self-hosted runners are **not** billed at all. The workflow (`.github/workflows/build.yml`) is split to minimize burn:

- **`check` (analyze + test)** → hosted `windows-2022` for PR / branch / main pushes. The suite is **not cross-platform** — `test/core/video/video_url_test.dart` asserts on Windows paths (`C:\…` → basename) and `test/ui/chat/chat_overlay_golden_test.dart` uses Windows-rendered goldens — so on Linux 4 tests fail; it must run on Windows (2×). **For tag pushes it runs on `[self-hosted, windows]` instead** — `build-windows-x64` has `needs: [check]`, so gating a tag's check on hosted-Actions availability would skip the free self-hosted Windows build whenever hosted Actions is unavailable; self-hosting the tag check keeps the test gate while making the release path independent of hosted minutes. (The real minute win is the self-hosted *build*, below — not the check.)
- **`build-windows-x64`** → `[self-hosted, windows]`. The expensive 2× Windows build runs on **our own PC** for free. Tag-push only.
- **`release`** (GitHub Release + R2 upload) → `ubuntu-latest`. Bash/rclone job, 1×. Tag-push only. This one **runs on hosted Linux**, so it needs hosted Actions to be available. **Failure path:** if a tag is pushed while hosted Actions is unavailable (budget cap reached, or minutes exhausted with no budget), the self-hosted `check` + `build-windows-x64` still produce the Windows artifact, but this `release` job fails or never starts — so **R2 is not updated and `latest.json` / `changelog.json` stay stale (the in-app updater keeps offering the old version).** The operator must then either **re-run the `release` job from the Actions UI once hosted Actions is restored** (no re-tag needed — re-running picks up the already-built artifact), or **manually publish** the build zip + a regenerated `latest.json` + `changelog.json` to R2. Fully self-hosting this job (rewriting its bash/rclone steps for Windows) would remove the dependency — a separate follow-up.

### Self-hosted Windows runner

Installed at `C:\actions-runner`, registered to this repo with the **`self-hosted` + `windows`** labels. It must be **online** for tag builds to run — otherwise the `build-windows-x64` job queues until a runner appears.

- **Toolchain:** on the self-hosted runner the workflow uses the **Flutter already installed via Puro** (`%USERPROFILE%\.puro\envs\stable\flutter\bin`), **not** `subosito/flutter-action`. That action shells out to bash for its setup script, which on this runner resolves to `wsl.exe` with no distro installed and exits 1 — so the `Setup Flutter` steps branch on `runner.environment`: hosted jobs use the action, self-hosted jobs prepend the Puro `bin` to `PATH`. `flutter build windows` also needs the **Visual Studio Desktop C++ workload**, so the runner must run under an account that can see that toolchain — run it as **the logged-in user**, not `NETWORK SERVICE`. (#154)
- **Start it (manual by design):** the runner is **not** auto-started — no service, no logon autostart (user's explicit choice; don't add one). Start it by launching `C:\actions-runner\run.cmd` before pushing a `v*` tag. Confirm it's live with `gh api repos/PeterShanxin/MeowWatch/actions/runners` (`status: online`). If a tag's `build-windows-x64` job sits **queued**, the runner is offline — start `run.cmd`.
- **If hosted Actions is unavailable** (included minutes *and* the Actions budget cap both spent): a **tag** push is unaffected for the build — its check + Windows build both run on the self-hosted runner for free — but the hosted `release` upload won't run (see the `release` failure path above: re-run it once hosted Actions is restored, or publish to R2 manually, else `latest.json`/`changelog.json` go stale). **PR/branch** checks (hosted `windows-2022`) are blocked — bridge those with the local-verification gate (see "When hosted Actions is unavailable" above).

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
3. If a manual test is warranted (visible behavior change), **request it only once the automated gates are clear** — bot reviews resolved/satisfied **and** CI green — never while a review or CI run is still pending. A new commit re-opens the gate, so a test exercised on a not-yet-final commit gets invalidated by the next change; the human's hands-on time is the scarce resource, so spend it once, on the version that will actually ship. (Building the Release artifact ahead of time is fine — just don't ask them to *exercise* it until the gates are clear.) Pure edge-case/defensive fixes with unit coverage don't need a manual test — say so. If the user already confirmed a manual test but later review/CI feedback requires any app-behavior patch, stop after CI/reviews clear, build/open the updated Release app again, and get a fresh manual confirmation before merging/tagging. Docs/comment/CI-only follow-ups do not invalidate an already-confirmed manual app test; say that explicitly.
4. Wait for **CI green** (the `Build / Analyze & Test` check — the PR gate). The full `Windows x64` build does **not** run on PRs; it runs only on the tag push. Then **merge** the PR to `main` (merge commit). _(If hosted Actions is ever unavailable — included minutes and the Actions budget cap both spent — use the local verification gate from "When hosted Actions is unavailable" above instead of waiting on this check.)_
5. `git checkout main && git pull` → **tag** `v<version>` on the merge commit → `git push origin v<version>`. The tag fires the build + release jobs (build → R2 upload + `changelog.json`). Since this is the *first* clean-room Windows build for the change, watch it — a build-only breakage surfaces here, not at PR time.
6. Wait for the release run green, then **verify R2**: `curl …/releases/latest.json` (version matches) and `…/releases/changelog.json` (array includes the new version).
7. **Wrap up** once R2 is verified — run the `call-it-a-day` skill (or do it by hand): `git checkout main && git pull` so main is the merge+tag commit, delete the merged branch (local + remote), prune the feature worktree under the active agent's worktree directory (for example, `.claude/worktrees/` or `.Codex/worktrees/`), remove session scratch files, and stop any leftover `meowwatch.exe` dev/test instances. End on a clean `git status` on `main`. Don't start this until after the merge, tag, and R2 verification — the worktree is still needed for PR iteration before then.

**Auto-update has a one-version lag:** the running app applies updates with *its own* (old) `buildUpdaterScript`, so a fix to the updater only takes effect for updates *from* the fixed version onward. After shipping an updater fix, that one hop must be installed **manually** (download the R2 zip, replace the install folder); auto-update works from the fixed version on. (The pre-0.1.3 updater used `Copy-Item -Recurse`, which nested `data\data\` and never replaced `app.so` — so 0.1.2→0.1.3 needs a manual install.)

## Maintaining this file

Keep this file current. When you discover a new sharp edge (a build quirk, a test trap, a non-obvious convention) or make a structural change to the architecture above, update the relevant section in the same change — don't let it drift. Prefer fixing/expanding an existing bullet over appending duplicates.

`CLAUDE.md` and `AGENTS.md` mirror a short, deliberate subset of this file — the highest-cost items agents kept missing (Puro Flutter path, the tag→R2 release chain, version lockstep, Release-build manual testing). If you change any of those four here, update the matching one-liner in **both** entrypoints in the same commit so they don't drift.
