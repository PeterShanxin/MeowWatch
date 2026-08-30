# Agent Guide

This file provides shared guidance for AI coding agents working in this repository.

Root tool entrypoints (`AGENTS.md`, `CLAUDE.md`) intentionally stay small and point here. Keep general repo guidance in this file; use root entrypoints only for tool-specific overrides.

**When you learn a general lesson** — a gotcha, a process rule, a fix worth not repeating — record it **here**, not only in a tool-specific or personal memory. Personal notes are private to one agent; this guide is what every agent and contributor inherits. Default to updating both.

MeowWatch is a Flutter **desktop** (Windows-first) co-watch app: load a local video, connect to a public Syncplay room, stay in sync with a friend, and chat over a floating overlay. Built in six phases (see `docs/ROADMAP.md`); Phases 1–2 shipped, Phase 3 (chat) in progress.

## Gotchas (read first — these have bitten us)

- **Flutter is installed via Puro and is NOT on PATH.** Always use
  `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat` (Puro stable).
  Plain `flutter` will fail unless that `bin` directory is on PATH.
- **Manual testing must use the Release build, not Debug.** A stale/Debug `meowwatch.exe` has caused "the fix isn't showing up" confusion. Verify the artifact you're launching is `build/windows/x64/runner/Release/meowwatch.exe`.
- **Dead-connection detection can't rely on socket `onDone`/`onError`.** A half-open TCP (server vanishes, NAT idle-eviction, Wi-Fi blip — peer never sends FIN/RST) leaves the socket "open" on our side: writes succeed into a black hole, no callback ever fires, and the app would sit on "connected" forever while chats go nowhere. `SyncplayClient` runs a `ConnectionWatchdog` that `bump()`s on every incoming byte and trips after `livenessTimeout` (12s ≫ the ~1s State heartbeat) → emits `reconnecting` → backed-off auto-reconnect. Don't remove it assuming the socket callbacks cover drops — they only cover *clean* closes. Relatedly, `disconnect()` uses `_socket.destroy()` not `close()`: `close()` awaits a flush that a half-open socket can never complete, which is what once wedged the "Leave room" button.
- **HW decode is the default; two instances on one PC need it forced OFF via env var.** `MediaKitVideoCore._configureDecoding()` defaults to hardware decode: `hwdec=d3d11va` on Windows (the **zero-copy** D3D11VA path — keeps decoded frames in GPU memory for media_kit's ANGLE texture path, avoiding the GPU→RAM→GPU copy-back `auto-safe` might pick; mpv auto-falls-back to software inside the decoder if d3d11va can't init), `hwdec=auto-safe` on every other platform (hardware decode on mpv's whitelist with automatic software fallback). Both are a big CPU/battery/heat win on Snapdragon X / Adreno. The catch: two app instances on one PC fight over the single HW decoder session — whichever opens its file *second* freezes at frame 0, and the sync layer then drags the healthy client backward forever (rewind-to-stay-together chasing the frozen peer). So for **two-instance-on-one-PC local testing**, set `MEOWWATCH_FORCE_SW_DECODE=1` before launching (PowerShell: `$env:MEOWWATCH_FORCE_SW_DECODE='1'`) — that flips back to `hwdec=no` and each instance decodes independently. Real two-machine use has one decoder per machine and needs nothing. The decision is pure logic in `video_decode_config.dart` (`resolveHwdec({forceSoftware, isWindows})` / `forceSoftwareDecodeFromEnv`), unit-tested in `test/core/video/video_decode_config_test.dart`. This HW-vs-SW split was once the root cause of a long "can't play in a room" hunt — the diagnostic was an `hwdec` contention issue, not the sync/auto-pause code.
- **`video-sync=display-resample` is always set; revert via env var if needed.** `_configureDecoding()` also sets `video-sync=display-resample` — this locks frame presentation to the monitor refresh rate (resampling audio slightly to maintain A/V lock) for smoother motion and fewer dropped frames. To revert to mpv's default audio-clock mode (e.g. for VRR/multi-monitor setups or sync debugging), set `MEOWWATCH_FORCE_AUDIO_SYNC=1` before launching. Pure logic in `video_decode_config.dart` (`resolveVideoSync` / `forceAudioSyncFromEnv`), unit-tested alongside the hwdec config. (#74)
- **Never emit a `Positioned` unless it's a *direct* child of a `Stack` — a misused one paints the whole screen translucent-white in release (#50).** `ChatOverlay` is mounted under `AnimatedOpacity > IgnorePointer` (see `HomeScreen`), **not** a Stack. Its drag/resize render path used to `return Positioned.fill(...)`; `Positioned` is a `ParentDataWidget` that requires a `RenderStack` parent, so that was a misuse. In **debug** it asserts; in **release** (asserts stripped) the bad parent-data slipped through and the engine composited the whole window wrong → a continuous translucent **pale-white wash over the entire screen for the whole drag**, on every theme, with or without a video. Fix: the overlay fills its own box with `SizedBox.expand`; the only `Positioned` lives inside the *inner* `Stack` that actually holds the card. Diagnosis traps that wasted hours here: the flash is **release-only** (debug renders it fine — don't conclude "fixed" from a debug run), it's **not** Impeller (repros with `--no-enable-impeller`), and **nothing in `lib/` is actually white** (all themes are dark) so it's never a widget colour. The old `chat_overlay_test.dart` missed it because its host wrapped the overlay in a `Stack`, which makes the misused `Positioned` legal — the regression guard in `chat_overlay_repaint_test.dart` mounts it under `IgnorePointer` like the real app. (#42's "hide the drop-zone hints during resize" was a red herring that never touched the real cause.) `ChatOverlay` also wraps its output in a `RepaintBoundary` — a separate repaint-isolation nicety, not the white-flash fix.
- **Dev/test builds share the production copy's data store unless you isolate them — set `MEOWWATCH_DATA_DIR`.** `getApplicationSupportDirectory()` derives its path from the exe *identity* (`com.shanxin`/`meowwatch`), **not** the exe's location, so a build run from this repo and a separately-installed production copy both resolve to the same `%APPDATA%\com.shanxin\meowwatch\` — sharing one `meowwatch.db` (and `logs/`). That single DB holds `last_seen_version`; two installs of different versions then ping-pong it and the post-update **What's new** modal misfires (showed up repeatedly on the user's production copy because in-dev test builds kept rewriting the key — confirmed in logs by the version alternating run-to-run). It also mingles dev and production logs in one folder. Fix is app-side (`lib/core/data/app_support_dir.dart` → `resolveAppSupportDir`, honored by the DB and the logger): launch any dev/test build with its own dir, e.g. PowerShell `$env:MEOWWATCH_DATA_DIR=(Join-Path $env:TEMP 'meowwatch-dev')` before `flutter run`/the Release exe. Production (env unset) is unaffected. Combine with `MEOWWATCH_WHATS_NEW=1` to exercise the modal in the isolated profile.
- **Kill running instances before `flutter build windows`.** A running `meowwatch.exe` holds a file lock; the linker can leave the **old** binary in place while the build still reports success. `Stop-Process -Name meowwatch -Force` first.
- **The `.exe` mtime is a red herring for Dart changes.** `meowwatch.exe` is the C++ runner and only changes when native code changes. Dart edits compile into `build/windows/x64/runner/Release/data/app.so` — check *that* timestamp to confirm a rebuild picked up Dart changes.
- **Stream emissions are async (microtask).** In tests, after pushing into a stream/calling a method that emits, `await Future<void>.delayed(Duration.zero)` before asserting on the result, or the assert runs before the listener fires.
- **Golden tests must be regenerated when their widget changes.** Editing a chat widget changes `test/ui/chat/goldens/*.png`; a plain `flutter test` then fails on mismatch. Re-run that test file with `--update-goldens` and visually inspect the PNG before committing.
- **`prefer_initializing_formals` false-positive:** private fields initialized from named params can't use initializing formals (named params can't start with `_`). Suppress per-file with `// ignore_for_file: prefer_initializing_formals` rather than restructuring.
- **Release builds must NOT `AttachConsole(ATTACH_PARENT_PROCESS)` — it adopts the updater's PowerShell console (#97).** The auto-updater relaunches us from inside its PowerShell process, so on startup the *parent* console is PowerShell's. The stock Flutter runner (`windows/runner/main.cpp`) calls `AttachConsole(ATTACH_PARENT_PROCESS)` to show `flutter run` logs — but in a shipped build that means the relaunched app **adopts PowerShell's console and keeps it alive after PowerShell exits**, leaving an empty console window lingering for the whole app session, whose **X button sends `CTRL_CLOSE_EVENT` straight to the app and kills it**. Fix: the `AttachConsole`/`CreateAndAttachConsole` block is guarded behind `#ifndef NDEBUG`, so it runs only in debug (`flutter run` logs preserved) and Release never adopts a parent console. Don't remove the guard to "get logs in release" — Release has no useful stdout and you'll resurrect the lingering-window + kill-switch bug. Pairs with `bringToFront()` in `lib/main.dart`: an updater-relaunched window also can't beat Windows' foreground-lock (it's launched by a background process), so it lands behind other windows; the `alwaysOnTop` true→false bump (`HWND_TOPMOST`, needs no foreground rights) raises it without pinning. Both are app-side, so they take effect on the *next* update, not the hop onto the fixed version's predecessor.
- **The auto-updater must be launched OUTSIDE the app's job object, or it dies on `exit(0)`.** The app runs inside a Windows job object; a detached child we spawn ourselves stays in that job, so the job's kill-on-close terminates it the instant the app exits — before it runs a single line. Symptom: clicking Install closes the app, nothing happens, version unchanged, no `updater.log` written. `applyUpdate` routes through `cmd /c start "" powershell …` (see `buildUpdaterLaunch`) so PowerShell is re-parented outside our process tree. Do NOT "simplify" this back to `Process.start('powershell', …)`. Verified by repro: detached powershell + immediate `exit(0)` ⇒ child killed; via `cmd start` ⇒ survives.
- **`jq` is NOT installed on this dev PC — use `gh`'s built-in `--jq` instead.** Piping `gh ... --json` into `jq` silently produces empty output (the shell reports `jq: command not found` into a stream nobody reads), so a watcher loop built that way reports "still waiting" forever while the thing it watches has already finished. `gh run view <id> --json status --jq '.status'` needs no external binary. PowerShell's `ConvertFrom-Json` is the other safe option.
- **`gh` CLI authentication failure:** AI sandbox environment injects invalid `GITHUB_TOKEN` environment variable. `gh` tool prioritize environment variable and ignore valid credentials in user system keyring. Always clear `GITHUB_TOKEN` before run `gh` command (e.g., `powershell -Command '$env:GITHUB_TOKEN=$null; gh ...'`).


## Commands

```bash
FLUTTER=%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat

$FLUTTER analyze                                   # lint/type check — keep at "No issues found!"
$FLUTTER test                                      # full suite
$FLUTTER test test/ui/chat/chat_bubble_test.dart   # single file
$FLUTTER test path/to/file_test.dart --plain-name "name"  # single test by name (--plain-name)
$FLUTTER test test/ui/chat/chat_overlay_golden_test.dart --update-goldens  # regenerate goldens
$FLUTTER build windows                             # Release exe (kill running instances first)
$FLUTTER run -d windows                            # debug run
```

### When hosted Actions is unavailable: the local gate

Hosted Actions is normally funded — the 3,000 included Pro minutes plus a small monthly **Actions budget** (a few dollars, with "stop usage when budget is reached" **on**). **Every pull request** runs analyze + test on GitHub-hosted Windows (2×). The self-hosted runner keeps the expensive **tag Windows build + sign** off the meter. Hosted overage is the PR Windows checks plus the 1× Ubuntu `gate` / `release` jobs.

Hosted Actions becomes **unavailable** only if both the included minutes *and* the budget cap are spent (or the budget is removed). When that happens hosted runs fail/stop instantly — **don't wait on or re-trigger the hosted check.** Use local verification on this dev PC as the substitute PR gate:

```bash
%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat analyze --no-pub
%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test --no-pub --concurrency=1 --reporter compact
```

Then build Release and do the manual test (see the Gotchas: kill build-path `meowwatch.exe` first, verify the rebuild via `build/windows/x64/runner/Release/data/app.so` mtime, launch the Release exe). Merge only after local analyze + test + build are green and the manual test passes.

## Continuous integration (CI)

The workflow (`.github/workflows/build.yml`) splits Windows check jobs so the
**privileged self-hosted host never runs pull-request code**. That host holds
the release-signing seed (`%USERPROFILE%\.meowwatch\release-key.txt`). Trusted
co-admins are **PeterShanxin** and **ianmeowmeow** (same host trust). **Every
`pull_request`** — forks, Dependabot, trusted-admin same-repo PRs, any other
login — takes **`check-hosted`** on GitHub-hosted **`windows-2022`**. Self-hosted
is **trusted-admin push/tag sign only**: analyze on push/`v*` tag, and tag
**Sign release**, and only when `github.actor` is in `{PeterShanxin,
ianmeowmeow}` (Dependabot excluded). Write access alone is not host trust.
GitHub's **fork-workflow approval does not cover a future write login adding
a new workflow**, so remaining self-hosted jobs keep the YAML `if:` allowlist.
GitHub-hosted Windows is billed at **2×**. Self-hosted runners themselves are
not billed.

- **PR gate (analyze + test)** → every `pull_request` takes **`check-hosted`**
  on `windows-2022`. There is no self-hosted PR path and no `ci-hosted` label.
  Hosted PR jobs (`check-hosted`, `gate`) use **`permissions: contents: read`
  only**. Hosted PR `actions/checkout` sets **`persist-credentials: false`**.
  Those jobs must **never** interpolate `TAURI_SIGNING_PRIVATE_KEY`, the
  MeowWatch Ed25519 seed / `MEOWWATCH_RELEASE_KEY` / `release-key.txt`,
  `R2_*` secrets, or `RELEASE_MIRROR_TOKEN`. The suite is **not
  cross-platform** — `test/core/video/video_url_test.dart` asserts on Windows
  paths (`C:\…` → basename) and `test/ui/chat/chat_overlay_golden_test.dart`
  uses Windows-rendered goldens — so on Linux 4 tests fail; the PR path must
  be Windows. Hosted image is **`windows-2022`**, not `windows-2025`: run
  33264970792 failed the two chat-overlay goldens on 2025 (0.05%/444px and
  15px). 2022 already ran untrusted PRs. Do not `--update-goldens` for 2025
  pixels.
  - **Push/tag analyze (`check-self-hosted`)** →
    **`[self-hosted, windows, meowwatch-ci]`**, only when `github.event_name !=
    pull_request` and `github.actor` is PeterShanxin or ianmeowmeow (not
    Dependabot). Any other login's branch or `v*` tag push does **not**
    schedule it.
  - **Single required check (`gate`)** → a tiny referee job on hosted Linux
    (1×, seconds) whose check-run name is exactly **`Analyze & Test`** (that
    exact string is the branch-protection context — **not** "Build / Analyze
    & Test", which is only the Checks-tab grouping by workflow name). It
    passes iff `check-hosted` went green. **`main` is protected to require
    `Analyze & Test`** (`strict:false`; `enforce_admins:false` so `--admin`
    still merges doc-only PRs that skip CI via `paths-ignore`; no required
    reviews — bot reviews gate by convention, not by rule), set via
    `gh api -X PUT repos/PeterShanxin/MeowWatch/branches/main/protection`.
    A queued self-hosted job on a PR is a bug — PRs never take that path.
- **`build-windows-x64`** → `[self-hosted, windows, meowwatch-ci]`. The
  expensive 2× Windows build runs on **our own PC** for free. **Tag-push only,
  and only when `github.actor` is PeterShanxin or ianmeowmeow** — pull requests
  cannot schedule it, and any other login's `v*` tag must not build or sign.
  Fork PRs never reach this job. Workflow default `permissions` are
  `contents: read`; this job is the one that gets `contents: write` to create
  GitHub Releases.
- **`release`** (GitHub Release + R2 upload) → `ubuntu-latest`. Bash/rclone job, 1×. Tag-push only. This one **runs on hosted Linux**, so it needs hosted Actions to be available. **Failure path:** if a tag is pushed while hosted Actions is unavailable (budget cap reached, or minutes exhausted with no budget), the self-hosted check + `build-windows-x64` still produce the Windows artifact, but this `release` job fails or never starts — so **R2 is not updated and `latest.json` / `changelog.json` stay stale (the in-app updater keeps offering the old version).** The operator must then either **re-run the `release` job from the Actions UI once hosted Actions is restored** (no re-tag needed — re-running picks up the already-built artifact), or **manually publish** the build zip + a regenerated `latest.json` + `changelog.json` to R2. Fully self-hosting this job (rewriting its bash/rclone steps for Windows) would remove the dependency — a separate follow-up. `secrets.R2_*` are referenced **only** in this job; PR jobs must never interpolate them.
- **`publish-showcase.yml`** → hosted Linux, **`workflow_dispatch` only**. It interpolates `secrets.RELEASE_MIRROR_TOKEN` to write the public MeowWatch-releases mirror. The job `if:` requires `github.actor` to be **PeterShanxin or ianmeowmeow**. GitHub evaluates that `if:` before the job starts, so any other login's click must not run it. Forks stay excluded.

### Self-hosted Windows runner

Registered to this repo with the **`self-hosted` + `windows` + `meowwatch-ci`** labels (those labels are what the workflow selects — not a machine hostname). It must be **online** for **PeterShanxin / ianmeowmeow** tag builds (and their push/tag `check-self-hosted`) — otherwise `build-windows-x64` or that check queues until a runner appears. **Pull requests never use this runner.** Any other login's tags do not sign. Do not invite outsiders to attach runners to this canonical repo.

Machine-local name and install directory live as parameters on `tool/runner.ps1` (`$RunnerName`, `$RunnerDir`). Do not copy those values into docs or issue text.

- **Toolchain:** on the self-hosted runner the workflow uses the **Flutter already installed via Puro** (`%USERPROFILE%\.puro\envs\stable\flutter\bin`), **not** `subosito/flutter-action`. That action shells out to bash for its setup script, which on this runner resolves to `wsl.exe` with no distro installed and exits 1 — so the `Setup Flutter` steps branch on `runner.environment`: hosted jobs use the action, self-hosted jobs prepend the Puro `bin` to `PATH`. `flutter build windows` also needs the **Visual Studio Desktop C++ workload**, so the runner must run under an account that can see that toolchain — run it as **the logged-in user**, not `NETWORK SERVICE`. (#154)
- **Start/stop it yourself, on demand — don't ask the user.** The runner is **not** auto-started — no service, no logon autostart (user's explicit choice; don't add one). The agent driving a release **starts it before pushing a `v*` tag and stops it once the release run is green and R2 is verified** — leaving it running idle is not the intent. Confirm it's live with `gh api repos/PeterShanxin/MeowWatch/actions/runners` (`status: online`, labels include `meowwatch-ci`) or `Get-Process Runner.Listener`. If a tag's `check-self-hosted` or `build-windows-x64` sits **queued**, the runner is offline. A self-hosted job queued on a **PR** is a workflow bug — PRs must stay on hosted Windows.
  - **On-demand lifecycle helper (`tool/runner.ps1`):** Run `pwsh tool/runner.ps1` (or `powershell -ExecutionPolicy Bypass -File tool/runner.ps1 start`). It idempotently:
    1. Confirms the repository runner registration via `gh api repos/PeterShanxin/MeowWatch/actions/runners` (matches `$RunnerName`).
    2. If GitHub has deleted the registration (auto-deleted after ~14 days idle): verifies no live runner processes need preserving, clears stale local config (`config.cmd remove --local`), mints a fresh registration token via API (kept in memory only, never written to disk), and re-registers the runner with `$RunnerName`, work dir `_work`, and custom label `meowwatch-ci`.
    3. If the runner is registered on GitHub but missing `meowwatch-ci`, adds the custom label via GitHub API.
    4. Syncs the action archive cache (`dart run tool/action_cache.dart sync`) before listener startup.
    5. Starts `$RunnerDir\run.cmd` detached via WMI `Win32_Process.Create` so the listener runs outside the caller's console session/Job Object and persists after the invoking shell exits (fails clearly with a diagnostic if WMI process creation fails; unconstrained `Start-Process` fallback is disabled because it cannot reliably escape the agent Job Object).
    6. Verifies through GitHub that `$RunnerName` reports `online` and carries all required labels (`self-hosted, Windows, X64, meowwatch-ci`).
  - **Process isolation & multi-runner safety:** Process inspection is strictly scoped to `$RunnerDir` by executable path/commandline matching. It never inspects or terminates other runner installations on the same PC.
  - **Status & safe stop:** Check status anytime with `pwsh tool/runner.ps1 status` (reports GitHub registration/version/labels + local target/processes). Stop with `pwsh tool/runner.ps1 stop`. `stop` fails closed: if the runner is busy on GitHub (`busy: true`) or a local worker process is active, it refuses to stop and exits non-zero to protect active CI jobs (including a pre-termination quiescence revalidation before terminating processes). Use `pwsh tool/runner.ps1 stop -Force` only for explicit manual overrides.
  - **Manual recovery (if not using helper):** `config.cmd remove --local` (the server-side registration is already gone, so the normal token remove has nothing to talk to), then `config.cmd --unattended --url https://github.com/PeterShanxin/MeowWatch --token <registration-token> --name <runner-name> --work _work --labels meowwatch-ci` (use the same `$RunnerName` as `tool/runner.ps1`), minting the token with `gh api -X POST repos/PeterShanxin/MeowWatch/actions/runners/registration-token --jq .token` and never writing it to a file. Custom labels like `meowwatch-ci` are NOT default and MUST be explicitly passed via `--labels meowwatch-ci` when re-registering or added via API (`gh api -X POST repos/PeterShanxin/MeowWatch/actions/runners/<id>/labels -f "labels[]=meowwatch-ci"`).
  - **Runner version & auto-updates:** GitHub delivers runner self-updates automatically to online listeners. Version drift is observable via `pwsh tool/runner.ps1 status` and the GitHub runner API without hardcoded version locks or in-place ZIP overwrites.
- **The action archive cache — without it, every job re-downloads `actions/checkout` and one bad response kills the job before a step exists.** The runner deletes `_work\_actions` at the *start* of every job (`ActionManager.PrepareActionsAsync`), so its own per-action watermark can never survive: 194 of 194 recorded jobs on this host downloaded, none reused a cached copy, and on 2026-07-12 one job burned four minutes losing two of its three attempts before scraping through. That download happens during job **initialization**, before any step exists, so `timeout-minutes` doesn't apply and a retry loop in a `run:` block is never reached — the runner just fails the job with `Caught exception from JobExtension Initialization`, naming `actions/checkout`, which reads like a broken workflow rather than an infrastructure limit. (#240)
  - **Fix:** `dart run tool/action_cache.dart sync` places the archives the workflows actually need under `$RunnerDir\action-archive-cache` and records that directory in `$RunnerDir\.env` as `ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE`. `ActionManager` then looks for `<cache>\<owner>_<repo>\<resolved-sha>.zip` and copies it instead of asking codeload. `dart run tool/action_cache.dart plan` shows what it would do without touching anything.
  - **The job log will not tell you whether it worked.** The runner prints `Download action repository 'actions/checkout@v7' (SHA:…)` *before* it consults the cache, so that line appears either way. The real signal is `Found action archive '<file>' in cache directory '<dir>'` in `$RunnerDir\_diag\Worker_*.log`.
  - **Never restart a live runner to apply it.** `.env` is read once, in `Program.LoadAndSetEnv`, when the listener starts; restarting mid-job can sever a dispatched job and there is no drain API. Since the runner is on-demand, syncing before you start it costs nothing.
  - **Don't share this runner's action-archive cache with another runner on the same machine.** A directory every job on both reads is a wider blast radius than the few megabytes it would save. MeowWatch's runner must not execute pull-request code.
- **If hosted Actions is unavailable** (included minutes *and* the Actions budget cap both spent): a **PeterShanxin or ianmeowmeow `v*` tag** push is unaffected for the build — its check + Windows build both run on the self-hosted runner for free — but the hosted `release` upload won't run (see the `release` failure path above: re-run it once hosted Actions is restored, or publish to R2 manually, else `latest.json`/`changelog.json` go stale). Any **other login's tag** does not take that self-hosted path. **Every PR** needs hosted Windows (`check-hosted` + `gate`), so no PR can pass CI while hosted Actions is down. Bridge with the local-verification gate (see "When hosted Actions is unavailable" above) and merge with admin override.
- **Runner hangs & watching a long run.** `flutter test` (occasionally `pub get` / the build) can wedge on the self-hosted runner — a stuck `flutter_tester` holds the job open with no progress. Each job now carries a **`timeout-minutes`** (checks 20/25, build 45, release 15) so a hang fails fast and frees the runner instead of sitting until GitHub's **6h default**; a timed-out run shows a clear status and re-runs with one click (no manual `flutter_tester` kill needed). The hang is flaky/environmental — the same commit passes on a clean retry — so the timeout is a backstop, not a root-cause fix. **Don't trust `gh run watch` for long self-hosted runs:** it has silently dropped the run mid-stream (~56 min in) and exited as if finished, hiding the hang. Poll `gh run view <run-id> --json status,conclusion,jobs` instead.
  - **One concrete, self-inflicted cause: local PC load.** The runner shares this dev PC, so a local `flutter build windows` (or a freshly launched app) running *while the runner executes the release's `Run tests` step* starves the tests past `timeout-minutes` → the tag run is **cancelled**, and because the test gate didn't pass, `build-windows-x64` + `release` (R2 publish) **skip** — nothing ships (happened on v0.33.0-alpha's first attempt). **Preventive:** do the final manual-test Release build *before* pushing the `v*` tag, then keep the PC idle while the release run is in flight. **Recover:** once idle, `gh run rerun <run-id>` — it re-uses the same run, and a green test step lets the build + R2 jobs proceed.
  - **Local test runs orphan `flutter_tester` processes — kill them before anything hits the runner.** A local full-suite `flutter test` (even one that passes) can leave several `flutter_tester.exe` orphans behind, and every failed/cancelled runner job orphans its own batch. Those orphans starve the *next* runner job: timing-sensitive tests flake, or the job hits `timeout-minutes`, or the runner dies outright with "runner lost communication with the server" — each of which strands more orphans, compounding. Rule of thumb (v0.40.0-alpha release): after every local suite run and between CI attempts, kill the leftover `flutter_tester.exe` processes, then rerun.
  - **Never blanket-kill `flutter_tester.exe` by image name — another agent/session on this dev PC may have a live test run in flight.** `taskkill /IM flutter_tester.exe` or `Stop-Process -Name flutter_tester` kills every match regardless of who spawned it; if a second Claude session (or a human) is mid-`flutter test` when you run this, you kill their testers too and hand them a confusing failure that isn't a real bug (happened 2026-07-13: a PR #201 rework session's cleanup killed PR #200 rework session's live testers). **Kill scoped to your own run's process tree, recorded *while it's still alive*** — walking the tree top-down *after* `flutter test` returns doesn't work: by then the intermediate `flutter.bat`/Dart launcher processes can already have exited, and `Win32_Process` only enumerates *live* processes, so a query for "children of that dead PID" finds nothing and the walk silently stops before it ever reaches the orphaned tester. Poll and union descendant PIDs *during* the run instead, then only kill still-running testers that were actually seen in that set:
    ```powershell
    $p = Start-Process powershell -ArgumentList '-NoProfile','-Command', $flutterTestCmd -PassThru
    $mine = New-Object System.Collections.Generic.HashSet[int]
    function Get-DescendantIds($rootId) {
      # @(...) forces array context — a single match collapses to a scalar PID
      # otherwise, and `+` then does integer addition instead of concatenation.
      $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$rootId" | Select-Object -ExpandProperty ProcessId)
      $kids + @($kids | ForEach-Object { Get-DescendantIds $_ })
    }
    while (-not $p.HasExited) {
      Get-DescendantIds $p.Id | ForEach-Object { $mine.Add($_) | Out-Null }
      Start-Sleep -Seconds 2
    }
    Get-CimInstance Win32_Process -Filter "Name='flutter_tester.exe'" |
      Where-Object { $mine.Contains($_.ProcessId) } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    ```
    If you only have a finished run to clean up after the fact (no live polling happened), a creation-time cutoff is a fallback, not a fix — only reach for it when you're confident no one else is testing concurrently.
  - **Before kicking off a full local suite run or a Release build, check whether the self-hosted runner is mid-job** (`gh run list` — anything `in_progress`/`queued` — or `gh api repos/PeterShanxin/MeowWatch/actions/runners` for `busy: true`). The runner shares this PC (see the PC-load bullet above), so heavy local work started while it's running a job starves that job the same way a release-time build does — just triggered from the dev side instead of the CI side. If a job's in flight, wait for it (or accept you may need to `gh run rerun` afterward).
- **Throttled/flaky network corrupts the media_kit archive downloads on tag builds.** The Windows build's CMake step (`media_kit_libs_windows_video`) downloads `ANGLE.7z` (~5 MB) and `mpv-dev-*.7z` (~9 MB) into `_work\MeowWatch\MeowWatch\build\windows\x64\`; on a throttled connection they arrive truncated → `Integrity check failed … Unable to generate build files`, or the download crawls until the job's 45-min timeout cancels it. Deleting the corrupt file and rerunning just re-downloads another corrupt copy, and pre-seeding good archives before the rerun doesn't survive — checkout's clean wipes `build/`. **What works (v0.40.0-alpha):** build the same commit locally first (its `build\windows\x64\*.7z` are verified-good), then run a small detached watcher loop that re-copies those archives into the runner's build dir every ~2 s for the duration of the rerun — it re-plants them right after checkout wipes the dir, CMake's hash check finds valid files, and the downloads are skipped entirely. Two consecutive integrity failures on *different* archives is the tell for network corruption rather than a stale cache.
- **GitHub can silently miss a push's PR-synchronize event.** The branch tip updates on the remote but the PR keeps pointing at the old head — no new CI run, no fresh bot review, and a later merge would ship the stale commit. Detect: `gh api repos/<o>/<r>/pulls/<n> --jq .head.sha` vs `git ls-remote origin <branch>` disagree minutes after the push (a healthy PR updates within seconds — observed on PR #209, 2026-07-17, stuck >15 min). Fix: push an **empty commit** (`git commit --allow-empty -m "chore: nudge PR synchronize"`) — the next push event re-syncs the PR. An amend + force-push also works but rewrites history for no benefit.
- **Job created while the runner was offline can stay queued even after it comes online.** If a **tag** run is created while the runner is **offline**, then you start the runner, GitHub often does **not** re-dispatch the already-queued `check-self-hosted` / `build-windows-x64` job to it — the job sits `queued` indefinitely even though `gh api repos/PeterShanxin/MeowWatch/actions/runners` shows the runner `status: online, busy: false` with matching `[self-hosted, windows, meowwatch-ci]` labels. **Fix:** force a fresh dispatch — `gh run cancel <run-id>` then `gh run rerun <run-id>` (the rerun re-queues and the now-online runner picks it up within seconds). Confirmed on PR #174: ~18 min stuck queued → cancel+rerun → picked up immediately. **Preventive:** start the runner *before* pushing a tag, so the job is created with a runner already online. Pull requests do not use this runner.

### Dependabot updates (dep-bump PRs)

Dependabot is configured (#210) to open grouped PRs for compatible pub bumps, plus separate PRs for major bumps and GitHub Actions updates. Lessons from the first batch (#211–#213 → v0.44.3-alpha, 2026-07-18):

- **Bot reviewers don't cover these.** Codex ignores dependabot PRs and Copilot may return only a quota stub — so the merge gate is **CI green + the usual quiet window**, not a bot 👍. Review the diff yourself: read the dependency's changelog for anything major (pub.dev `/changelog`), and check how the app actually uses the package before trusting a green suite.
- **Merge lock-touching PRs one at a time, rebasing the rest between merges.** Two dep PRs both rewrite `pubspec.lock`; after the first merges, GitHub may still show the second as cleanly mergeable because the hunks don't overlap — but its lock was *solved against the old dep set* and its CI ran on the stale base. Comment **`@dependabot rebase`**, wait for the force-push + fresh CI on the combined set, then merge. Dependabot PRs run on **hosted Windows**, not the self-hosted runner.
- **The same staleness bites any dep PR left open across an unrelated release** — not just two lock PRs racing each other. A dep PR still based on the pre-release `main` shows up `BLOCKED` with a confusing mixed check history (old cancelled/failed runs alongside newer green ones). Don't try to reason about which run is authoritative: `@dependabot rebase`, let CI re-run on the current base, merge that.
- **Bumping a codegen tool needs a generated-code diff, not just a green suite.** `drift_dev` regenerates `lib/core/data/app_database.g.dart`, which is committed — a passing test run only proves the *checked-in* file still compiles, not that it still matches what the new tool emits. After merging such a bump, run `dart run build_runner build` on the merged dep set and diff the generated files. If they're identical (line-ending noise aside), commit nothing; if they differ, the regenerated output belongs in the follow-up chore PR. Note `--delete-conflicting-outputs` is removed in current build_runner — it warns and ignores the flag, so plain `build` is what you want.
- **Dep bumps are behavior-changing but dependabot can't bump our version lockstep.** After merging a dependabot batch, land a small follow-up `chore` PR that bumps `pubspec.yaml` + `lib/core/app_version.dart` + `CHANGELOG.md` (patch bump; user-facing note like "library refreshes under the hood"), run the local gate on the merged dep set, then release it as normal (manual smoke test → merge → tag → verify R2). Manual test should target the surfaces the bumped packages own (e.g. playback for `media_kit_*`, fullscreen/resize for `window_manager`, drag-drop for `desktop_drop`).

### Release signing (auto-update trust root)

Every release is signed with an **Ed25519** key so the app installs only genuine builds. The download's SHA-256 lives in the *same R2 bucket* as the zip, so anyone who can swap the zip can swap the hash to match — it only catches corruption, not tampering. The signature is the real trust root because the private key never touches the bucket. The signature covers a **domain-separated manifest of the version + the zip's SHA-256**, not the raw bytes alone — so a compromised bucket can't replay an old, genuinely-signed zip under a faked higher `version` in latest.json (a rollback/downgrade attack); the app rejects any zip whose advertised version isn't the one that was signed (`releaseSignedMessage` in `lib/core/update/release_signature.dart`).

- **Keys.** The private **seed** lives ONLY on the release PC at `%USERPROFILE%\.meowwatch\release-key.txt` (override the path with the `MEOWWATCH_RELEASE_KEY` env var) — never in the repo, GitHub secrets, or R2. The matching **public** key is baked into the app as `releasePublicKeyBase64` in `lib/core/update/release_signature.dart`. Generated 2026-07-06.
- **Signing is automatic on tag builds.** The `Sign release` step in `build.yml` runs `dart run tool/release_signer.dart sign …` on the self-hosted runner, producing `MeowWatch-windows-x64.zip.sig`; the R2 `release` job embeds it into `latest.json` as the asset's `sig`. **Tag-push only** — no PR or fork can invoke the signing step, so the key is only ever read on a maintainer-created tag. The signer refuses to sign if the seed's public half doesn't match the baked-in key (guards against signing a release the app would reject).
- **Fail-closed both ends.** No key on the runner ⇒ the tag build **fails** (won't ship unsigned). App side: `applyUpdate` refuses any download whose `sig` is missing or doesn't verify. So **every release must be signed** — a release that goes out unsigned would brick existing installs' updaters. If you ever publish to R2 **by hand** (the hosted-`release`-down recovery path in the CI section), sign first: `dart run tool/release_signer.dart sign --version <version> <keyfile> MeowWatch-windows-x64.zip MeowWatch-windows-x64.zip.sig` — `<version>` **must** equal the `version` you write into `latest.json` (the signature binds it) — then paste that base64 into `latest.json`'s `sig` field.
- **Custody caveats.** **Losing** the key ⇒ you can't ship updates existing installs will accept (back it up somewhere safe). `tool/release_signer.dart genkey <out>` mints a fresh keypair (refuses to overwrite an existing file).
- **Rotating is a two-release dance** (existing installs verify against the key *they* already carry, so the switch can't be abrupt):
  1. **Transitional release** — bake the *new* public key, but sign with the **OLD** private key so current installs still accept it. For the automatic CI path, set the repo/workflow variable **`MEOWWATCH_ALLOW_KEY_MISMATCH=true`** for just that one tag build (the `Sign release` step then adds `--allow-key-mismatch`), and clear it afterwards. By hand: `dart run tool/release_signer.dart sign --version <v> --allow-key-mismatch <old-key> MeowWatch-windows-x64.zip MeowWatch-windows-x64.zip.sig`. Without the override the signer refuses (the seed's public half won't match the newly-baked key).
  2. **Next release onward** — sign with the **new** key normally (no flag); by now installs carry the new public key. Skipping step 1's old-key signing means existing installs can't verify the update and (correctly) refuse it.

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

**Glue:** `PlaybackSyncBridge` wires `VideoCore` ⇄ `SyncCore` (local playback → outgoing State; incoming peer state → local seek/pause via `decideFollow`). Room identity and Syncplay participation are separate: every player session has a real room/server/port, and `SessionMode` (`local` / `synced`) says whether that session is currently in Syncplay. `HomeScreen` owns a `SessionServices` host that can `startSynced` / `stopToLocal` on the same player — Local Start skips the trio; the in-player Local toggle starts or tears it down without recreating MediaKit. `SessionChrome.forMode` is the one UI gate; `selectSessionBanner` keeps media/load transients in local while dropping derived sync banners. The lobby toggle (`kLocalPlayerModeSettingKey`) is the default for Start / Continue Watching only — join-code and saved rooms stay synced for that session and do not persist Local=false. History progress is per watch context (`local` or `synced|server|port|room`), not per file. A Local row keeps the `local` context key while retaining its session's random room/server/port as display and resume metadata. Continue Watching restores its saved position before a synced session connects, so the initial room state cannot race it back to 0:00. Those Start/Continue actions await the first settings load so a persisted ON cannot race the default-off seed. An explicit lobby toggle bumps a revision so a stale in-flight read cannot overwrite the newer choice.

**Chat data flow:** sending delegates to `SyncCore.sendChat`; the server echoes the sender's own message back to the whole room, so messages land via the normal receive path. There is **no optimistic local insert** — the stream is the single source of truth.

**Immutability:** state objects (`PlaybackState`, `ChatMessage`, `ChatOverlayLayout`, etc.) are `@immutable` with `copyWith`; never mutate in place.

**Theme (Phase 3, hardcoded "Cozy"; theming arrives in Phase 5):** warm dark `0xFF1A1410`, card fill `0xF2241B14`, amber accent `0xFFD4A574`, cream text `0xFFF5E6D3`, dim text `0x99F5E6D3`, border `0x55D4A574`.

## Workflow

TDD (RED → GREEN → REFACTOR), small commits at verified milestones. Conventional-commit messages (`feat:`, `fix:`, …). Don't tag a phase complete until the user confirms a manual two-instance test passes. Specs live in `docs/superpowers/specs/`, per-phase plans in `docs/superpowers/plans/`.

**Versioning (every behavior-changing PR):** bump the version in lockstep across `pubspec.yaml` (`version:`), `lib/core/app_version.dart` (`appVersion`), and `CHANGELOG.md` (new top `## [<version>] - <date>` entry).

### Motion

Timing + easing live in `lib/core/theme/tokens/motion.dart` (`Motion.*`). New
work draws from these tokens, never ad-hoc durations. Honor reduce motion via
`context.reduceMotion` (`lib/core/theme/reduce_motion.dart`) — it's true when
the OS "reduce animations" setting is on; every motion primitive (`RevealIn` in
`lib/ui/motion/`, `LaunchReveal` in `lib/ui/launch/`) degrades to an instant
present when it is. The cold-start `LaunchReveal` overlays the lobby and must
never block input (skippable on any click/key); it's the reason the post-update
"What's new" modal fires from the reveal's `onComplete`, not before. Reduce
motion is driven solely by the OS "reduce animations" accessibility setting (read
via `context.reduceMotion`) — there is no in-app toggle. Lobby motion primitives
draw from the `Motion.*` tokens: `fadeUpRoute` (`lib/ui/motion/fade_up_route.dart`)
is the rise+fade room push, and `StaggeredReveal`
(`lib/ui/motion/staggered_reveal.dart`) is the cold-start card cascade (both lobby
columns ripple in together) — both go instant under reduce motion.

**Degrading an `AnimatedSize` under reduce motion means dropping it, not
zeroing it.** `duration: Duration.zero` looks like the obvious degraded form and
is what a reviewer will suggest, but a zero-duration `AnimatedSize` re-dirties
itself inside its own `performLayout` and throws *"A RenderAnimatedSize was
mutated in its own performLayout implementation"*. Return the child directly
instead (see `_ExpandSize` in `lib/ui/player_menu_button.dart`). Zero duration is
fine for `AnimatedRotation`, `AnimatedOpacity`, and route transitions — it is
specifically the layout-animating widget that breaks.

The reveal shows one rotating tip under the wordmark, drawn from `kLaunchTips`
in `lib/ui/launch/launch_tips.dart` (the reveal picks one per launch by a
per-run seed). **When you add a user-facing keystroke, gesture, or feature
worth surfacing, add a one-line tip there** — keep it true of the shipping app
and short enough to sit on one row (the test enforces this). Nothing else to
wire; the bigger pool is picked up automatically.

The hidden **design gallery** (`lib/ui/gallery/`, reachable via the version-badge
long-press or `MEOWWATCH_GALLERY=1`) is the living motion showcase — it drives
the real `Motion.*` tokens and primitives, so it can't drift from what ships.
**When you add a motion token, name it in the `Motion` section's chips and, if
it's a curve, give it a racer (monotonic easings) or a live specimen in
`Motion · principles` (overshoot/wind-up curves).** New primitives get a demo
section (see `Motion · pressable` / `Motion · reveal`). The gallery's
**Reduce motion** toggle (a gallery-only `ReduceMotionScope` override, not a
global setting) previews the degraded form across every specimen. Gallery loops
run forever — tests pump fixed durations, never `pumpAndSettle`, and the lazy
`ListView` means bottom sections must be step-scrolled into view first.

### Changelog writing style

The in-app "What's new" screen renders each version's notes. Write them for the
end user:

- Lead with an optional `> one-line summary` — it becomes the hero/row headline.
  Omit it and the app derives one from the first line.
- Group changes under `### Added`, `### Fixed`, or `### Improved` so the New /
  Fixed / Improved chips appear. `### Changed` also maps to Improved.
- For a punchier chip, append a short custom label: `### Improved: Better
  changelog` renders an amber-bolt chip reading "Better changelog" (the word
  before the `:` still picks the category + color; the rest is the label). A
  bare `### Improved` falls back to the generic "Improved".
- A version with no `###` sections (older free-form entries) still gets one chip
  inferred from its version number: a patch (`0.31.2`) shows **Fixed**, a minor
  or major (`0.32.0`, `1.0.0`) shows **New**. Add explicit `###` sections when
  the inference would be wrong (e.g. a patch that's really an improvement).
- Keep internal mechanism ("Future", "single-flight", "robocopy") in the commit
  message, not the note. Describe what the user sees change.
- Issue refs `(#NNN)` render as tappable links — leave them in.
- Supported formatting: `**bold**`, `` `code` ``, bullets, paragraphs.

Semver is `MAJOR.MINOR.PATCH` — **three separate digit slots**, each is the digit *in that position*, NOT "the next number overall":
- `MAJOR` = **1st** digit — big/breaking change. Bumping it resets MINOR and PATCH to 0 (`0.2.3 → 1.0.0`).
- `MINOR` = **2nd** digit — new feature. Bumping it resets PATCH to 0 (`0.1.3 → 0.2.0`, **not** `0.1.4`).
- `PATCH` = **3rd** digit — bug fix / small tweak (`0.1.3 → 0.1.4`).

So a `feat:` PR is a MINOR bump = 2nd digit + reset 3rd to 0. A `fix:` PR is a PATCH bump = 3rd digit. Common mistake: bumping the 3rd digit and calling it "minor" — the 3rd digit is PATCH.

Keep the `-alpha` suffix until we move off alpha. CI parses `CHANGELOG.md` → `releases/changelog.json` on R2, which the in-app updater reads — so the three files drifting out of sync breaks the updater's "what changed" view.

**Release flow (the user finds this sequence helpful — follow it for every release):**
1. Land the work on a feature/fix branch and get it **locally green** (analyze + test). **If the change has visible/UX surface, do an early local look BEFORE opening the PR:** build the Release and open it so the user can inspect/test while iteration is still cheap — no PR, bots, or gates involved yet — and fold in their feedback (possibly several rounds). Once the user is happy with the look (or for non-visual changes, right away), **open a PR to `main`.** Don't push `v*` tags from the branch. This is the *early* checkpoint; step 3's manual test is the *final* one on the shippable commit — two distinct looks.
2. Wait for the automatic **Copilot review**, then run the `address-pr-review` skill: fix or reject each comment with a real reason, reply, resolve the threads, push.
3. If a manual test is warranted (visible behavior change), **request it only once the automated gates are clear** — bot reviews resolved/satisfied **and** CI green — never while a review or CI run is still pending. A new commit re-opens the gate, so a test exercised on a not-yet-final commit gets invalidated by the next change; the human's hands-on time is the scarce resource, so spend it once, on the version that will actually ship. (Building the Release artifact ahead of time is fine — just don't ask them to *exercise* it until the gates are clear.) Pure edge-case/defensive fixes with unit coverage don't need a manual test — say so. If the user already confirmed a manual test but later review/CI feedback requires any app-behavior patch, stop after CI/reviews clear, build/open the updated Release app again, and get a fresh manual confirmation before merging/tagging. Docs/comment/CI-only follow-ups do not invalidate an already-confirmed manual app test; say that explicitly.
4. Wait for **CI green** (the `Analyze & Test` check — the PR gate, now required by branch protection on `main`). **Every PR** runs on hosted Windows (`check-hosted` → `gate`). Do **not** start the self-hosted runner for a PR; it is for trusted-admin push/tag sign only. The full `Windows x64` build does **not** run on PRs; it runs only on a **PeterShanxin or ianmeowmeow** tag push (`github.actor`). Then **merge** the PR to `main` (merge commit). _(If hosted Actions is ever unavailable — included minutes and the Actions budget cap both spent — use the local verification gate from "When hosted Actions is unavailable" above instead of waiting on this check.)_
5. `git checkout main && git pull` → **tag** `v<version>` on the merge commit → `git push origin v<version>`. The tag fires the build + release jobs (build → R2 upload + `changelog.json`). Since this is the *first* clean-room Windows build for the change, watch it — a build-only breakage surfaces here, not at PR time.
6. Wait for the release run green, then **verify R2**: `curl …/releases/latest.json` (version matches) and `…/releases/changelog.json` (array includes the new version).
7. **Wrap up** once R2 is verified — run the `call-it-a-day` skill (or do it by hand): `git checkout main && git pull` so main is the merge+tag commit, delete the merged branch (local + remote), prune the feature worktree under the active agent's worktree directory (for example, `.claude/worktrees/` or `.Codex/worktrees/`), remove session scratch files, and stop any leftover `meowwatch.exe` dev/test instances. End on a clean `git status` on `main`. Don't start this until after the merge, tag, and R2 verification — the worktree is still needed for PR iteration before then.

**Auto-update has a one-version lag:** the running app applies updates with *its own* (old) `buildUpdaterScript`, so a fix to the updater only takes effect for updates *from* the fixed version onward. After shipping an updater fix, that one hop must be installed **manually** (download the R2 zip, replace the install folder); auto-update works from the fixed version on. (The pre-0.1.3 updater used `Copy-Item -Recurse`, which nested `data\data\` and never replaced `app.so` — so 0.1.2→0.1.3 needs a manual install.)

## Maintaining this file

Keep this file current. When you discover a new sharp edge (a build quirk, a test trap, a non-obvious convention) or make a structural change to the architecture above, update the relevant section in the same change — don't let it drift. Prefer fixing/expanding an existing bullet over appending duplicates.

`CLAUDE.md` and `AGENTS.md` mirror a short, deliberate subset of this file — the highest-cost items agents kept missing (Puro Flutter path, the tag→R2 release chain, version lockstep, Release-build manual testing). If you change any of those four here, update the matching one-liner in **both** entrypoints in the same commit so they don't drift.
