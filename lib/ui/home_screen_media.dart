part of 'home_screen.dart';

/// The media seam of [_HomeScreenState] (#182): loading a source (browse /
/// paste link / drop / resume), confirming it opened, announcing it to the
/// room, resume-position persistence, and leaving the room.
mixin _HomeMediaState on _HomeScreenStateBase, _HomeSyncState {
  @override
  bool _leavingRoom = false;

  /// The source path that the *most recent* load actually confirmed open. The
  /// connect/reconnect re-announce gates on this so a still-loading, superseded,
  /// or failed source is never re-sent to the room — and so a valid live stream
  /// (which stays `paused` with no duration) still reannounces, where the bare
  /// state alone couldn't tell it apart from the pre-error paused tick. Set on a
  /// confirmed open in [_load], invalidated when a new load starts.
  @override
  String? _loadedSource;

  /// True while a [_browse] is between its click and the file picker appearing.
  /// The picker preflight now awaits (DB read + folder probes) before the modal
  /// opens, so the UI stays live in that gap; without this guard a second Load
  /// Video click would queue a second picker (#144 review).
  bool _browsing = false;

  /// Bumped at the start of every [_load]. Browse/Paste/drop stay reachable
  /// while a load is in flight, so a newer load can supersede an older one that's
  /// still awaiting its async open result. Each [_load] captures its generation
  /// and abandons quietly at every `await` boundary once it's no longer current,
  /// so a stale load can't fail, record, announce, or chat against the source a
  /// newer load now owns.
  int _loadGeneration = 0;

  /// Live "Finding the video…" progress while a page URL is being resolved
  /// through yt-dlp. A notifier so only the banner subtree rebuilds (same
  /// rationale as [_presenceNotice], #196); null = nothing in flight.
  final ValueNotifier<String?> _resolveNotice = ValueNotifier<String?>(null);

  /// Seam for tests: swap the real yt-dlp pipeline for a fake.
  @visibleForTesting
  ResolveFlow? debugResolveFlow;

  ResolveFlow get _resolveFlow => debugResolveFlow ??= ResolveFlow();

  Timer? _historyTimer;
  // Serializes the periodic resume-position save and skips a write whose
  // (file, position, duration) match the last one that succeeded, so a
  // paused room doesn't hammer SQLite with identical values every 5s (#206).
  final _resumeSaveGate = ResumeSaveGate();

  /// Load (but do not auto-play). In a room, hitting play yourself starts both
  /// of you in sync; auto-playing on load made the two clients fight at 0.
  ///
  /// Returns `true` only if *this* load opened and is still the current source —
  /// callers (e.g. resume) can then act on it; a `false` means it failed, timed
  /// out, or was superseded by a newer load.
  ///
  /// [isResolveRetry] marks the one automatic re-run this method grants itself
  /// when a yt-dlp-resolved link is rejected by mpv (#228) — it exists only to
  /// stop that retry from retrying. Callers never pass it.
  Future<bool> _load(String path, {bool isResolveRetry = false}) async {
    // We now have a video, so the "load a video to join" prompt is moot (#60).
    if (_joinPrompt != null && mounted) setState(() => _joinPrompt = null);
    // This load's generation. A newer load bumps it; we abandon at every await
    // boundary below once we're no longer current, so a stale/slow load can't act
    // on a core state that now belongs to a different source.
    final gen = ++_loadGeneration;
    // Redacted name only (a URL's signed token must never hit disk). A "load"
    // line with no matching "opened"/"open failed" line localizes a load-time
    // freeze (#139) the old sync-only log couldn't see (#140).
    appLog('video: load ${mediaDisplayName(path)}');
    // Page URLs (YouTube, Bilibili, …) resolve to real streams via yt-dlp
    // BEFORE the core or any announce state is touched: a failed resolve leaves
    // whatever was playing (and its room announce) fully intact, and the room
    // only ever sees the stable page URL — each peer resolves locally, because
    // extracted stream links are signed, short-lived, and often IP-bound.
    ResolvedMedia? resolved;
    if (needsResolver(path)) {
      resolved = await _resolvePageUrl(
        path,
        gen,
        retryNotice: isResolveRetry ? kResolvedOpenRetryNotice : null,
      );
      // Failed or superseded — surfaced inside _resolvePageUrl.
      if (resolved == null) return false;
      // Resolving can await for many seconds (first-run tool download + the
      // network resolve). The user may have left the room in that window, and
      // dispose() does NOT bump _loadGeneration — so also honor `mounted`
      // before touching the process-shared player, or a completed resolve would
      // reopen the abandoned room's media into the next session (Codex P1).
      if (!mounted || gen != _loadGeneration) return false;
    }
    // Invalidate the accepted-source marker until this load is confirmed, so a
    // reconnect mid-load can't re-announce the previous source.
    _loadedSource = null;
    // Drop the previous file's byte size now, before the new load opens. Until
    // _recordOpen commits the new size, a stale positive size would let
    // _fileMismatchBanner / compareFiles judge match-by-size against a source
    // that never opened (compareFiles trusts equal sizes ahead of URL identity),
    // so the load/error screen could wrongly show a peer as matching.
    if (_localFileSizeBytes != null && mounted) {
      setState(() => _localFileSizeBytes = null);
    }
    if (resolved != null) {
      await _core.loadResolved(resolved);
    } else {
      await _core.load(path);
    }
    // A source can fail asynchronously — mpv reports an unreachable / non-video
    // / expired URL, *and* a moved or unreadable local file, on its error stream
    // after load() returns. Don't record it to history, announce it to the room,
    // or post a "Loaded …" chat line until it actually opens, or a failed source
    // would surface to peers and history as loaded while we show the error
    // screen. Applies to local files too, not just URLs.
    final opened = await awaitOpenResult(_core, source: path);
    // Superseded while we awaited: a newer load owns the core now, so do nothing
    // here (no failLoad, no announce) — the newer load reports its own outcome.
    if (gen != _loadGeneration) {
      appLog('video: load superseded ${mediaDisplayName(path)}');
      return false;
    }
    if (!opened) {
      // A signed CDN link that yt-dlp resolved cleanly and mpv then refused
      // outright: re-resolve once and open the fresh link — exactly what the
      // user was doing by hand with "Try again" (#228). Only for a hard
      // rejection, only once, only for a page URL (see [shouldRetryResolvedOpen]).
      // The recursive call bumps the generation, becoming the current load, so
      // it owns the outcome from here.
      if (mounted &&
          _core.state.filePath == path &&
          shouldRetryResolvedOpen(
            wasResolved: resolved != null,
            alreadyRetried: isResolveRetry,
            status: _core.state.status,
          )) {
        appLog('video: open rejected ${mediaDisplayName(path)} — re-resolving');
        return _load(path, isResolveRetry: true);
      }
      // Distinguish the two ways an open fails to confirm: mpv rejecting the
      // source (error) versus never answering at all (a real hang). The old
      // line called both a timeout.
      final rejected = _core.state.status == PlaybackStatus.error;
      appLog(
        'video: open failed ${mediaDisplayName(path)} '
        '(${rejected ? 'rejected' : 'timed out'})',
      );
      // A load that never confirmed open must be surfaced as an error, or the
      // user is stuck on a frozen surface with no recovery buttons (those only
      // show on PlaybackStatus.error). This covers both a plain `loading` hang
      // and a source forced to `playing`/`paused` over a never-opened URL (e.g. a
      // peer heartbeat applying play() while we were still loading). Guard on the
      // path so we never force the error onto a different source, and `failLoad`
      // itself no-ops if the source did genuinely open. A rejection already sits
      // in the error state with mpv's own message, so only the hang needs the
      // synthesized timeout copy.
      if (!rejected && _core.state.filePath == path) {
        _core.failLoad('Timed out waiting for the video to open.');
      }
      return false;
    }
    if (!mounted || _core.state.filePath != path) return false;
    appLog('video: opened ${mediaDisplayName(path)}');
    final size = await _recordOpen(path);
    // _recordOpen awaits file-size/DB work; a newer load could have started and
    // swapped the core state (and _localFileSizeBytes) meanwhile.
    if (gen != _loadGeneration || !mounted) return false;
    _loadedSource = path;
    // Tell the sync bridge this source is confirmed open so its heartbeat
    // accepts the source's ticks — essential for a live/direct stream that never
    // reports a duration (the bridge can't infer "open" from such a stream).
    _bridge.markSourceOpen(path);
    _announceLoadedFile(path, sizeBytes: size);
    // `dispose()` doesn't bump the generation, so guard on `mounted` too.
    if (gen != _loadGeneration || !mounted) return false;
    // Compare against the peer's announced file once; both the chat line and the
    // over-video banner key off the same verdict so they can't contradict (#178).
    final match = compareFiles(
      localName: _core.state.fileName,
      localSize: _localFileSizeBytes,
      peerName: _peerFile?.name,
      peerSize: _peerFile?.sizeBytes,
    );
    _addLoadedFileMessage(match);
    // Brief over-video confirmation that the load landed and we're in sync with
    // a friend (the chat line is easy to miss on the video). Silent solo, while a
    // friend hasn't loaded yet, or on a mismatch — see [loadedInSyncNotice].
    final notice = loadedInSyncNotice(match: match);
    if (notice != null && mounted) {
      setState(() => _showTransientNotice(notice));
    }
    return true;
  }

  /// Resolve a page URL through yt-dlp, driving the [_resolveNotice] banner
  /// while it runs. Returns null when the resolve failed or this load was
  /// superseded — failures are surfaced here: while a video is already open we
  /// show a transient notice (never nuke live playback over a bad paste), on
  /// the empty/load screen we drive the error surface via [VideoCore.failSource]
  /// so the user gets recovery buttons, not a silent nothing.
  Future<ResolvedMedia?> _resolvePageUrl(
    String pageUrl,
    int gen, {
    String? retryNotice,
  }) async {
    // On the automatic re-resolve (#228) the banner says why we're going round
    // again; the first attempt just says we're looking.
    _resolveNotice.value = retryNotice ?? 'Finding the video…';
    try {
      final resolved = await _resolveFlow.run(
        pageUrl,
        onStatus: (status) {
          // dispose() bumps the generation and disposes the notifier; guard
          // both so a late status callback never writes a disposed notifier.
          if (mounted && gen == _loadGeneration) _resolveNotice.value = status;
        },
      );
      if (gen != _loadGeneration) return null;
      appLog('video: resolved ${mediaDisplayName(pageUrl)}');
      return resolved;
    } on ResolveException catch (e) {
      if (gen != _loadGeneration) return null;
      // Kind only — e.detail can embed the URL's signed token; never log it.
      appLog(
        'video: resolve failed ${mediaDisplayName(pageUrl)} (${e.kind.name})',
      );
      final message = friendlyResolveError(e.kind);
      if (isPlaybackOpen(_core.state)) {
        if (mounted) setState(() => _showTransientNotice(message));
      } else {
        _core.failSource(pageUrl, message);
      }
      return null;
    } finally {
      // A newer load (or teardown) owns the notice now; only clear it if we
      // still do and the notifier is still alive.
      if (mounted && gen == _loadGeneration) _resolveNotice.value = null;
    }
  }

  /// Append a "Loaded …" system line to chat. Shows "in sync!" when the peer's
  /// file matches ours; otherwise just names the file. Replaces the misleading
  /// "jumped to 00:00" that appeared on first load (#91).
  void _addLoadedFileMessage(FileMatch match) {
    final fileName = _core.state.fileName;
    if (fileName == null) return;
    // Match on the full name (URL identity); show the short label in chat.
    _chat.addSystem(
      loadedFileMessage(fileName: mediaDisplayName(fileName), match: match),
    );
  }

  Future<void> _resume(String path, int positionMs) async {
    // Only seek if this resume load actually opened and is still current —
    // otherwise a superseded/failed load would apply the old position to
    // whatever the user picked instead. seekWhenReady is also scoped to [path]
    // so a load that supersedes it during the duration-wait can't inherit this
    // resume position.
    if (await _load(path)) {
      await seekWhenReady(
        _core,
        Duration(milliseconds: positionMs),
        source: path,
      );
    }
  }

  Future<int> _recordOpen(String path) async {
    final state = _core.state;
    // A stream URL has no byte size — don't stat it as a file (the URL isn't a
    // valid path, and on Windows the ':' would throw a different error).
    final size = isHttpUrl(path) ? 0 : await _fileSize(path);
    // `_localFileSizeBytes` is the *current* file's size, used for the
    // file-match comparison. Only commit it while this load is still current —
    // a slow stat for a superseded file would otherwise overwrite the new
    // file's size and trigger a false mismatch against a peer on the same file.
    if (mounted && _core.state.filePath == path) {
      setState(() => _localFileSizeBytes = size);
    }
    // Best-effort + logged: a history write must never crash a load, and a
    // recordOpen line with no match localizes a DB stall (#140).
    try {
      await widget.history.recordOpen(
        filePath: path,
        fileName: state.fileName ?? path,
        fileSizeBytes: size,
        durationMs: state.duration.inMilliseconds,
        room: widget.config.room,
        username: widget.config.username,
        server: widget.config.server,
        port: widget.config.port,
      );
      appLog('db: recordOpen ok ${mediaDisplayName(path)}');
    } catch (e) {
      appLog(
        'db: recordOpen FAILED ${mediaDisplayName(path)}: ${redactUrls('$e')}',
      );
    }
    // A periodic save may have baselined a snapshot while the stat/DB work
    // above was in flight, and recordOpen may have partially rewritten that
    // row — drop the baseline so the next tick re-writes current truth
    // (#208 review).
    _resumeSaveGate.reset();
    return size;
  }

  /// [force] always writes (used by leave/dispose so the final position is
  /// never dropped); a normal periodic tick goes through [_resumeSaveGate],
  /// which serializes writes and skips one that would just repeat the last
  /// successful save (#206).
  Future<void> _saveResumePosition({bool force = false}) async {
    final state = _core.state;
    final path = state.filePath;
    if (path == null) return;
    // Only persist a resume point for a source that actually opened. A failed or
    // still-loading load leaves filePath set at position 0 (e.g. an expired URL
    // or a moved local file retried from history), and saving that would erase
    // the real saved position for that history row.
    if (!isPlaybackOpen(state)) return;
    // `trace:` — this runs every few seconds, so it's firehose kept only at
    // verbose; neat drops it (#140).
    try {
      await _resumeSaveGate.attempt(
        filePath: path,
        positionMs: state.position.inMilliseconds,
        durationMs: state.duration.inMilliseconds,
        force: force,
        write: () async {
          // False = no history row yet (recordOpen still in flight); the
          // gate then retries on the next tick instead of treating the
          // silent no-op as saved (#208 review).
          final wrote = await widget.history.updatePosition(
            filePath: path,
            positionMs: state.position.inMilliseconds,
            durationMs: state.duration.inMilliseconds,
          );
          if (wrote && appLogInstance?.level == LogLevel.verbose) {
            appLog(
              'trace: db updatePosition ${mediaDisplayName(path)} '
              '@${state.position.inMilliseconds}ms',
            );
          }
          return wrote;
        },
      );
    } catch (e) {
      appLog(
        'db: updatePosition FAILED ${mediaDisplayName(path)}: ${redactUrls('$e')}',
      );
    }
  }

  Future<void> _leave() async {
    if (_leavingRoom) return;
    // setState so the banner clears this frame (see [_banner]) — the resume-save
    // await below holds the room on screen for up to 600ms before we pop.
    if (mounted) {
      setState(() => _leavingRoom = true);
    } else {
      _leavingRoom = true;
    }
    appLog('life: leave room (button)');
    _historyTimer?.cancel();
    if (isPlaybackOpen(_core.state)) {
      try {
        await _saveResumePosition(
          force: true,
        ).timeout(const Duration(milliseconds: 600));
      } on Object catch (e) {
        appLog('life: leave resume-save skipped: ${redactUrls('$e')}');
      }
    }
    final cleanup = _finishLeaveCleanup();
    if (mounted) Navigator.of(context).pop();
    appLog('life: returned to connect screen');
    unawaited(cleanup);
  }

  Future<void> _finishLeaveCleanup() async {
    try {
      await _sync.disconnect().timeout(const Duration(milliseconds: 800));
    } on Object catch (e) {
      appLog('life: leave disconnect cleanup skipped: ${redactUrls('$e')}');
    }
    try {
      await (_syncLog?.flush() ?? Future<void>.value()).timeout(
        const Duration(milliseconds: 500),
      );
    } on Object catch (e) {
      appLog('life: leave log flush skipped: ${redactUrls('$e')}');
    }
  }

  /// Whether the just-(re)connected room should be told about the current
  /// source — see [canAnnounceOnConnect] for the rule.
  @override
  bool _shouldReannounceOnConnect() => canAnnounceOnConnect(
    currentPath: _core.state.filePath,
    acceptedPath: _loadedSource,
    status: _core.state.status,
  );

  @override
  void _announceLoadedFile(String? path, {int? sizeBytes}) {
    if (path == null) return;
    // For a URL, size is unknown (streams have no byte length) and the URL
    // itself is the name we share — matching official Syncplay.
    if (_loadedSource != path || !mounted) return;
    final size = isHttpUrl(path) ? 0 : (sizeBytes ?? _localFileSizeBytes ?? 0);
    final state = _core.state;
    final fallbackName = isHttpUrl(path) ? path : mediaDisplayName(path);
    appLog('sync: announce file ${mediaDisplayName(path)}');
    _sync.announceFile(
      name: state.filePath == path
          ? (state.fileName ?? fallbackName)
          : fallbackName,
      size: size,
      duration: state.filePath == path ? state.duration : Duration.zero,
    );
  }

  /// Byte size of a local file, or 0 if it can't be read.
  Future<int> _fileSize(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> _browse() async {
    // A preflight or picker is already in flight: a second click would queue a
    // duplicate picker now that the preflight awaits before the modal opens
    // (#144 review).
    if (_browsing) return;
    _browsing = true;
    String? path;
    try {
      final typeGroup = XTypeGroup(
        label: 'Video',
        extensions: videoExtensions.toList(),
      );
      // Open the picker in a concrete local folder, never the Windows
      // Quick-access view whose recent/cloud scan can hang the
      // (UI-thread-blocking) dialog and freeze the whole app (#139).
      final initialDirectory = await _pickerInitialDirectory();
      // The preflight awaits (DB read + folder probes); if the screen went away
      // meanwhile, a stale click must not open a dialog or load into reset
      // state (#144 review).
      if (!mounted) return;
      final file = await openFile(
        acceptedTypeGroups: [typeGroup],
        initialDirectory: initialDirectory,
      );
      if (file == null || !mounted) return;
      path = file.path;
    } finally {
      // Release the guard once the picker closes — only the preflight+picker
      // window can queue a duplicate. Holding it through _load would block the
      // user from picking a replacement while a slow/stuck open runs, breaking
      // the load-generation supersede flow (#144 review r3).
      _browsing = false;
    }
    // Outside the guard: a newer browse may now supersede this load. `path` is
    // promoted non-null here — every no-file/unmounted branch above returns
    // inside the try (after the finally clears the guard).
    await _load(path);
  }

  /// Best-effort folder to open the file picker in (#139): the last-watched
  /// video's folder, else the most recent history entry's folder, else Videos /
  /// home.
  ///
  /// Each candidate is probed by [_isDirResponsive] before use. Existence alone
  /// is not enough: a history folder on a disconnected mapped drive or a
  /// cloud-backed (OneDrive) folder can still `exists()` yet stall when
  /// `IFileDialog::Show` synchronously navigates into it on the UI thread —
  /// reintroducing the freeze this fixes (#144 review). The probe runs off the
  /// UI isolate under a timeout, so a slow/stale candidate is skipped (never
  /// awaited to completion) and we fall through to the next, local one.
  Future<String?> _pickerInitialDirectory() async {
    String? recentFilePath;
    try {
      final recent = await widget.history
          .watchRecent(limit: 1)
          .first
          .timeout(const Duration(seconds: 1));
      if (recent.isNotEmpty) recentFilePath = recent.first.filePath;
    } catch (_) {
      // DB slow or unavailable — fall through to the env folders.
    }
    return resolvePickerInitialDirectory(
      lastLoadedFilePath: _loadedSource,
      recentFilePath: recentFilePath,
      environment: Platform.environment,
      isDirectoryUsable: _isDirResponsive,
    );
  }

  /// Whether [path] is a directory the file picker can open *without stalling*.
  ///
  /// We don't just check existence: a UNC / mapped-drive / cloud-backed folder
  /// can answer `exists()` but then hang the shell while it enumerates, which
  /// would freeze `IFileDialog::Show` on the UI thread (#144 review). So we
  /// actually enumerate one entry — `dart:io` async listing runs off the UI
  /// isolate, and the timeout caps a stalled folder so the UI never blocks. A
  /// folder that responds quickly here is one the picker can navigate quickly.
  /// A non-existent folder, a permission error, or a timeout all read as
  /// unusable.
  Future<bool> _isDirResponsive(String path) {
    return Directory(path)
        .list(followLinks: false)
        .isEmpty
        .then((_) => true)
        .timeout(const Duration(milliseconds: 800), onTimeout: () => false)
        .catchError((_) => false);
  }

  /// Prompt for a direct video link and load it through the same path as a
  /// local file. The URL is validated inside the dialog before it resolves.
  Future<void> _promptPasteLink() async {
    final url = await showPasteLinkDialog(context);
    if (url != null) await _load(url);
  }

  void _handleDropped(String path) {
    unawaited(_load(path));
  }
}
