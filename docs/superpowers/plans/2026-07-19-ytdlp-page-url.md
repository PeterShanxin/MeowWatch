# Paste a Page URL (yt-dlp) Implementation Plan — issue #123 (+ #124 outline)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paste a YouTube/Bilibili/any-page URL → app resolves the real stream via yt-dlp and plays it; the room shares the *page* URL and each peer resolves locally.

**Architecture:** New pure module `lib/core/resolve/` (classifier → provisioner → resolver → error mapper) feeding a new header-aware open path in `MediaKitVideoCore`. yt-dlp.exe (+ Deno for YouTube) is **downloaded on first use** into the app data dir (`<dataDir>/tools/`) — NOT bundled in the release zip (bundling would bloat every update by ~17 MB and the updater's robocopy would roll back a self-updated yt-dlp; #124 self-update requires the exe to live in a user-writable dir we own).

**Tech Stack:** Dart `Process.run` (injectable seam), `http` (already dep), media_kit 1.2.6 `Media(httpHeaders:)` + `setAudioTrack(AudioTrack.uri(...))`.

## Global Constraints

- Flutter binary: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat` (Puro, not on PATH)
- Version lockstep: `pubspec.yaml` → `0.45.0-alpha+1`, `lib/core/app_version.dart` → `0.45.0-alpha`, `CHANGELOG.md` new top entry (feat = MINOR bump)
- `flutter analyze` must stay "No issues found!"; full `flutter test` green
- Immutable data patterns; files < 800 lines; no hardcoded secrets
- Resolver invocation (fixed by research): `yt-dlp -J --no-playlist -I 1 -f "bv*+ba/b" --ignore-config --no-warnings --socket-timeout 10 --retries 2 -- <URL>`, 60 s app-side hard kill
- Always propagate resolved format `http_headers` into `Media(httpHeaders:)` (Bilibili 403s without Referer)
- Room share stays the **page URL** via existing Syncplay `Set.file` name (zero protocol change)
- Downloads only from official GitHub release endpoints over HTTPS, yt-dlp verified against its `SHA2-256SUMS` asset

## Key recon facts (for implementers with zero context)

- A1 load chain: `lib/ui/home_screen_media.dart:45 _load` → `lib/core/video/media_kit_video_core.dart:198 load` → `_player.open(Media(source), play: false)` at `:223`.
- URL share: `_announceLoadedFile` (`home_screen_media.dart:291`) sends the loaded source string verbatim as Syncplay file name (`lib/core/video/video_url.dart:37 mediaSourceName`). Peer receives it, `home_screen_sync.dart:287-320` builds a `JoinPrompt` whose button calls `_load(url)` — so peers automatically go through the same resolve path. **Nothing to change in sync code as long as the page URL (not the resolved CDN URL) is what `mediaSourceName` returns for a resolved load.**
- Process-spawn test seam pattern to copy: `UpdateService.debugStartDetached` (`lib/core/update/update_service.dart:143`), `open_external.dart debugUrlLauncherOverride`.
- Data dir: `lib/core/data/app_support_dir.dart resolveAppSupportDir` (honors `MEOWWATCH_DATA_DIR`).
- Friendly error surface: `lib/ui/video_error_state.dart` + `friendlyPlaybackError` (`lib/core/video/video_url.dart:60`).
- Error taxonomy stderr markers (from yt-dlp source): `DRM protected`, `Unsupported URL`, `geo restriction`/`available in your country`, `Private video`/`Video unavailable`/`Sign in`, `Unable to download`/`timed out`/`getaddrinfo`/`WinError`.
- JSON result: single-format → top-level `url` + `http_headers`; split → `requested_formats` array of 2 (video first, audio second), each with `url` + `http_headers`.
- Launch tips: append one line to `kLaunchTips` in `lib/ui/launch/launch_tips.dart`.

---

### Task A: Pure resolve core — classifier, result model, error mapper, resolver

**Files:**
- Create: `lib/core/resolve/url_classifier.dart`
- Create: `lib/core/resolve/resolved_media.dart`
- Create: `lib/core/resolve/resolve_error.dart`
- Create: `lib/core/resolve/yt_dlp_resolver.dart`
- Test: `test/core/resolve/url_classifier_test.dart`, `test/core/resolve/resolve_error_test.dart`, `test/core/resolve/yt_dlp_resolver_test.dart`

**Interfaces (Produces):**
```dart
// url_classifier.dart
/// True when the URL is an http(s) page that needs yt-dlp (not a direct media file).
bool needsResolver(String url); // false for .mp4/.mkv/.webm/.m3u8/.ts/.mov/.avi/.mp3/.m4a/.aac/.flac/.ogg/.opus/.wav (query strings stripped before sniff), false for non-http

// resolved_media.dart
class ResolvedMedia {
  final String pageUrl;        // original page URL — what the room shares
  final String videoUrl;       // stream URL for Media()
  final String? audioUrl;      // second URL when formats were split
  final Map<String, String> httpHeaders; // from the chosen format's http_headers (video format wins)
  final String? title;
  const ResolvedMedia({required this.pageUrl, required this.videoUrl, this.audioUrl, this.httpHeaders = const {}, this.title});
}

// resolve_error.dart
enum ResolveErrorKind { toolMissing, unsupportedSite, drm, geoBlocked, unavailable, network, timeout, unknown }
class ResolveException implements Exception { final ResolveErrorKind kind; final String detail; }
ResolveErrorKind mapYtDlpStderr(String stderr); // substring match, order: drm → unsupported → geo → unavailable → network → unknown
String friendlyResolveError(ResolveErrorKind kind); // end-user copy, e.g. drm → "This site protects its videos, so they can't be played here."

// yt_dlp_resolver.dart
typedef ProcessRunner = Future<ProcessResult> Function(String exe, List<String> args);
class YtDlpResolver {
  YtDlpResolver({required String exePath, ProcessRunner? runner, Duration timeout = const Duration(seconds: 60)});
  Future<ResolvedMedia> resolve(String pageUrl); // throws ResolveException
}
```

- [ ] Write failing tests: classifier table (page URLs true, direct media false, playlist query URL true, non-http false); stderr mapper table (one real stderr line per kind); resolver parse of (a) single-format JSON, (b) `requested_formats` split JSON with bilibili-style `http_headers`, (c) `"_type": "playlist"` JSON → ResolveException(unsupportedSite-or-unknown with "playlist" detail), (d) exit 1 + DRM stderr → drm, (e) runner that never completes → timeout kind (use short injected timeout), (f) malformed JSON → unknown.
- [ ] Run: `%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat test test/core/resolve/ --no-pub` → FAIL (missing files)
- [ ] Implement the four files. Resolver builds exactly the Global-Constraints arg list, runs via injected `runner` (default `Process.run` with `stdoutEncoding/stderrEncoding: utf8`), races the timeout, picks video/audio URLs + headers from JSON.
- [ ] Tests green; commit `feat: add yt-dlp resolve core (classifier, resolver, error mapping)`

### Task B: Header-aware open path in MediaKitVideoCore

**Files:**
- Modify: `lib/core/video/video_core.dart` (interface), `lib/core/video/media_kit_video_core.dart`
- Test: `test/core/resolve/resolved_load_test.dart` (+ update existing VideoCore fakes only if the interface addition forces it — prefer a default no-op impl on the base class so fakes stay untouched)

**Interfaces (Produces):**
```dart
// video_core.dart — base class gains (non-abstract, default delegates to load(pageUrl) — keeps all fakes compiling):
Future<void> loadResolved(ResolvedMedia media) => load(media.pageUrl);
```
- `MediaKitVideoCore.loadResolved` mirrors `load` (`media_kit_video_core.dart:198-251`): same generation/loading-status/`awaitOpenResult` flow, but `fileName: mediaSourceName(media.pageUrl)` (so Syncplay announces the page URL) and opens `Media(media.videoUrl, httpHeaders: media.httpHeaders.isEmpty ? null : media.httpHeaders)`; after open, if `media.audioUrl != null` → `await _player.setAudioTrack(AudioTrack.uri(media.audioUrl!))`.

- [ ] Failing test: fake/subclass records that announced name == page URL and opened URL == videoUrl (follow existing `test/core/video/video_core_test.dart` fake style)
- [ ] Implement; run `flutter.bat test test/core/ --no-pub` green; commit `feat: header-aware resolved-media open path in video core`

### Task C: Tool provisioner (download yt-dlp + Deno on first use)

**Files:**
- Create: `lib/core/resolve/tool_provisioner.dart`
- Test: `test/core/resolve/tool_provisioner_test.dart`

**Interfaces (Produces):**
```dart
class ToolProvisioner {
  ToolProvisioner({required Directory toolsDir, http.Client? client});
  /// Returns path to a ready yt-dlp.exe, downloading yt-dlp.exe (+ deno.exe) on first call.
  /// onStatus emits user-facing progress ("Setting up the video finder…").
  Future<String> ensureYtDlp({void Function(String status)? onStatus}); // throws ResolveException(toolMissing/network)
}
```
Behavior:
- toolsDir = `<resolveAppSupportDir()>/tools`. If `yt-dlp.exe` exists → return immediately (no version check on hot path).
- Download `https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe` and `.../SHA2-256SUMS`; verify sha256 of the exe against the SUMS entry; write `yt-dlp.exe.part` then rename (atomic-ish).
- Deno (YouTube JS runtime, yt-dlp auto-detects it beside its exe): download `https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip`, extract `deno.exe` into toolsDir (use `package:archive` like the updater; reuse zip-slip guard pattern from `lib/core/update/` if extractable, else validate the single entry name == `deno.exe`). Verify with the release's `.sha256sum` sidecar if present; otherwise HTTPS + non-empty + PE magic (`MZ`) check. Deno failure is NON-fatal: log + continue (YouTube degraded, other sites fine).
- All HTTP via injected `http.Client` (tests use `MockClient` — copy `test/core/update/apply_harness.dart:88` pattern).

- [ ] Failing tests: fresh dir → downloads both, verifies sha, returns path; existing exe → no network calls; bad checksum → throws toolMissing, no exe left behind; deno download failure → still returns yt-dlp path.
- [ ] Implement; green; commit `feat: on-demand yt-dlp/deno provisioning with checksum verification`

### Task D: UI wiring — resolve state, friendly errors, tip, third-party note

**Files:**
- Modify: `lib/ui/home_screen_media.dart` (`_load`), `lib/ui/home_screen_body.dart` (resolving notice), `lib/ui/launch/launch_tips.dart`
- Modify: `lib/core/video/video_url.dart` only if error-copy helpers need sharing
- Create: `THIRD_PARTY_NOTICES.md` (yt-dlp Unlicense/GPLv3-exe credit, Deno MIT — we download official builds at runtime, still credit)
- Test: `test/ui/resolve_flow_test.dart`, update `test/ui/launch/launch_tips_test.dart` count if asserted

Behavior in `_load` (home_screen_media.dart:45), before `_core.load(path)`:
```dart
if (needsResolver(path)) {
  _setResolving('Finding the video…');            // ValueNotifier<String?> rendered like SyncHintBanner / EmptyState notice
  try {
    final exe = await ToolProvisioner(toolsDir: ...).ensureYtDlp(onStatus: _setResolving);
    final resolved = await YtDlpResolver(exePath: exe).resolve(path);
    _setResolving(null);
    await _core.loadResolved(resolved);           // announces page URL to room
  } on ResolveException catch (e) {
    _setResolving(null);
    _failWithMessage(friendlyResolveError(e.kind), detail: e.detail);  // → VideoErrorState surface
    return;
  }
} else { await _core.load(path); }
```
Guards: tie into the existing load-generation counter (`home_screen_media.dart:49`) so a stale resolve result never loads; user can paste something else meanwhile.
Launch tip (append): `'Paste a YouTube or Bilibili page link — MeowWatch digs out the video for you.'`

- [ ] Failing widget/flow test with fake provisioner+resolver injected (add small seams: `@visibleForTesting` factory overrides on the mixin)
- [ ] Implement; green; commit `feat: paste a page URL — resolve via yt-dlp and play (#123)`

### Task E: Version bump + changelog + full local gate

- [ ] `pubspec.yaml` `version: 0.45.0-alpha+1`; `lib/core/app_version.dart` `appVersion = '0.45.0-alpha'`; CHANGELOG top entry:
```markdown
## [0.45.0-alpha] - 2026-07-19
> Paste a YouTube or Bilibili link — the video just plays.
### Added
- Paste a page link (YouTube, Bilibili, and many more) and MeowWatch finds the actual video behind it (#123). Your room mate gets the same one-click "Watch this too" — their app finds the video on their side, so links never go stale.
- First use sets up a small helper (yt-dlp) automatically — nothing to install.
```
- [ ] `flutter.bat analyze --no-pub` → "No issues found!"; `flutter.bat test --no-pub --concurrency=1 --reporter compact` → all green; kill stale `flutter_tester` after
- [ ] Commit `chore: bump to 0.45.0-alpha`

### Task F: Early Release build + user manual test (BEFORE PR)

- [ ] Kill build-output `meowwatch.exe` only (never the copy in D:\MeowWatch-windows-x64); `flutter.bat build windows`; verify `build/windows/x64/runner/Release/data/app.so` mtime
- [ ] Hand to user: paste a YouTube link + a Bilibili link, check "Finding the video…" state, playback (YouTube needs Deno download to have succeeded), room-share prompt on second instance
- [ ] Fold in feedback, then PR → gates (Copilot/Codex + CI) → user final test → merge → tag `v0.45.0-alpha` → verify R2

### #124 outline (separate PR after #123 merges)

- `ToolProvisioner.maybeUpdate()`: background `yt-dlp.exe -U --ignore-config` at most once/day (persist `kYtDlpLastUpdateCheckKey` in SettingsStore); never blocks resolve; on resolve failure + outdated → one retry after update; offline → silent skip. Log `--version` into verbose logs. Patch→`0.45.1-alpha` or minor per content.
