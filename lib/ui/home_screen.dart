import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../core/audio/notify_sounds.dart';
import '../core/chat/chat_store.dart';
import '../core/connect/room_config.dart';
import '../core/connect/room_share.dart';
import '../core/data/history_mode.dart';
import '../core/data/settings_store.dart';
import '../core/data/stores.dart';
import '../core/data/watch_context.dart';
import '../core/debug/app_log.dart';
import '../core/debug/debug_log.dart';
import '../core/debug/log_archive.dart';
import '../core/debug/log_level.dart';
import '../core/debug/log_redact.dart';
import '../core/sync/auto_pause.dart';
import '../core/sync/file_match.dart';
import '../core/sync/join_prompt.dart';
import '../core/sync/loaded_file_message.dart';
import '../core/sync/loaded_notice.dart';
import '../core/sync/presence_messages.dart';
import '../core/sync/room_greeting.dart';
import '../core/sync/roster_banner.dart';
import '../core/sync/peer_files.dart';
import '../core/sync/peer_state.dart';
import '../core/sync/playback_sync_bridge.dart';
import '../core/sync/sync_activity_throttle.dart';
import '../core/sync/syncplay_client.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/motion.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/resolve/open_retry.dart';
import '../core/resolve/resolve_error.dart';
import '../core/resolve/resolve_flow.dart';
import '../core/resolve/resolved_media.dart';
import '../core/resolve/url_classifier.dart';
import '../core/resolve/url_normalize.dart';
import '../core/session/session_mode.dart';
import '../core/session/session_services.dart';
import '../core/video/media_kit_video_core.dart';
import '../core/video/video_engine_pool.dart';
import '../core/video/load_coordinator.dart';
import '../core/video/picker_initial_directory.dart';
import '../core/video/playback_screen_view.dart';
import '../core/video/playback_state.dart';
import '../core/video/seek_when_ready.dart';
import '../core/video/source_announce.dart';
import '../core/video/video_url.dart';
import 'app_close_hook.dart';
import 'chat/chat_corner.dart';
import 'chat/chat_overlay_layout.dart';
import 'chat/chat_overlay_region.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'idle_rearm_throttle.dart';
import 'idle_visibility.dart';
import 'load_video_choices.dart';
import 'notify_decision.dart';
import 'player_menu_button.dart';
import 'reactions/floating_reactions.dart';
import 'reactions/reaction_bar.dart';
import 'resume_save_gate.dart';
import 'sync_activity_text.dart';
import 'sync_hint_banner.dart';
import 'video_error_state.dart';
import 'video_surface.dart';

// The room screen is split along its seams into part files (#182): each seam
// is a private mixin on [_HomeScreenStateBase], assembled in [_HomeScreenState]
// below. All parts share this library, so private members cross files freely
// and the split is purely structural.
part 'home_screen_body.dart';
part 'home_screen_chat.dart';
part 'home_screen_idle.dart';
part 'home_screen_media.dart';
part 'home_screen_sync.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.config,
    required this.history,
    required this.settings,
    required this.currentTheme,
    required this.onThemeChanged,
    this.initialWidthPx,
    this.initialHeightPx,
    this.initialCorner,
    super.key,
  });

  final RoomConfig config;
  final HistoryStore history;
  final SettingsStore settings;
  final double? initialWidthPx;
  final double? initialHeightPx;

  /// The chat card's persisted docked corner; null falls back to the default.
  final ChatCorner? initialCorner;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// The shared spine of the room screen's state: the engine/room/log handles
/// plus the small focus/log/settings helpers that several seams touch. The
/// full state object is assembled in [_HomeScreenState] by mixing the seam
/// mixins — idle ([_HomeIdleState]), sync/presence ([_HomeSyncState]), chat
/// ([_HomeChatState]), media ([_HomeMediaState]) and the widget tree
/// ([_HomeBody]) — onto this base; one part file per seam (#182).
abstract class _HomeScreenStateBase extends State<HomeScreen> {
  late final MediaKitVideoCore _core;
  late final SessionServices _session;
  late SessionChrome _chrome;

  bool get _isSynced => _session.isSynced;
  bool get _isLocal => _session.isLocal;

  WatchContext get _historyContext => watchContextForSession(
    local: _session.isLocal,
    server: widget.config.server,
    port: widget.config.port,
    room: widget.config.room,
  );

  bool _shouldLog({required bool verboseOnly}) {
    final level = appLogInstance?.level;
    return level == LogLevel.verbose ||
        (!verboseOnly && level == LogLevel.neat);
  }

  /// Implemented on [_HomeScreenState]: live Local ↔ synced switch.
  Future<void> _setEffectiveLocalMode(bool local);

  /// In-flight [_setEffectiveLocalMode]. Leave awaits this so a toggle's
  /// persist is visible to the lobby before `_loadSettings` runs.
  Future<void>? _modeSwitch;

  SyncplayClient? get _sync => _session.sync;
  PlaybackSyncBridge? get _bridge => _session.bridge;
  ChatStore? get _chat => _session.chat;

  /// The process-wide rotating diagnostic log, installed once at startup in
  /// `main()` and shared by the lobby, every room, and the update service
  /// (#140). Held as a getter (not a field) so HomeScreen reads the same
  /// instance everyone else writes to — it never owns, creates, or closes it.
  /// Null only if the log dir was unavailable, in which case the gear's
  /// export/level controls degrade gracefully.
  DebugLog? get _syncLog => appLogInstance;
  LogLevel _logLevel = LogLevel.verbose;
  HistoryMode _historyMode = HistoryMode.latestPerRoom;
  late final Player _audioPlayer;

  /// Keyboard focus for the player. Held here (not inside VideoSurface) so that
  /// after the chat collapses — which removes its auto-focused text field — we
  /// can hand focus straight back to the player. Otherwise focus falls to the
  /// root and the next Tab is wasted just re-acquiring it (the "press Tab twice"
  /// bug). With focus always on a descendant, the Tab handler fires every press.
  final FocusNode _videoFocus = FocusNode(debugLabel: 'video-surface');

  /// Fallback keyboard-focus holder for when no video is loaded (so the empty /
  /// "waiting" screen still has a focused descendant for the Tab handler to fire
  /// from). skipTraversal keeps it out of Tab focus-traversal; we only ever
  /// focus it programmatically when restoring focus with no VideoSurface mounted.
  final FocusNode _rootFocus = FocusNode(
    debugLabel: 'home-root',
    skipTraversal: true,
  );
  late String _username;
  String _primarySoundId = kDefaultPrimarySoundId;
  String _secondarySoundId = kDefaultSecondarySoundId;

  /// Apply a new diagnostic-log level live and persist it.
  void _onLogLevelChanged(LogLevel level) {
    // Log the change at the *current* level first — switching to `off` closes
    // the sink, so a line emitted afterward would be dropped.
    appLog('settings: log level=${level.storageName}');
    setState(() => _logLevel = level);
    _syncLog?.level = level;
    widget.settings.set(kLogLevelSettingKey, level.storageName);
  }

  /// Bundle the rotating logs into a single zip the user picks a location for,
  /// so they can send us the evidence after a laggy session.
  Future<void> _exportLogs() async {
    final dir = _syncLog?.dir;
    if (dir == null) {
      _showLogSnack('No diagnostic logs to export yet.');
      return;
    }
    // Push the live session's buffered lines to disk first, or the zip would
    // omit the most recent (and most relevant) trace.
    await _syncLog?.flush();
    // Zip in a background isolate — this can run mid-playback (#197 P4).
    final zipBytes = await zipLogFilesInBackground(dir.path);
    if (zipBytes == null) {
      _showLogSnack('No diagnostic logs to export yet.');
      return;
    }
    try {
      final location = await getSaveLocation(
        suggestedName: 'meowwatch-logs.zip',
      );
      if (location == null) return; // user cancelled
      await File(location.path).writeAsBytes(zipBytes);
      _showLogSnack('Saved diagnostic logs.');
    } on Object {
      _showLogSnack('Could not save the logs.');
    }
  }

  void _showLogSnack(String text) {
    if (!mounted) return;
    final m = context.meow;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: m.surface,
          content: Text(text, style: TextStyle(color: m.textPrimary)),
        ),
      );
  }

  /// True only while a real [VideoSurface] is on screen — not on the empty/load
  /// screen and not on the load-error screen (which shows [VideoErrorState], so
  /// `_videoFocus` is attached to nothing). Mirrors the `videoVisible` gate in
  /// [build] so focus is always requested on a node that actually exists.
  bool get _videoSurfaceMounted =>
      _core.state.fileName != null &&
      _core.state.status != PlaybackStatus.error;

  /// Put keyboard focus on whichever node is live for the current screen so the
  /// top-level Tab handler always has a focused descendant to bubble from and
  /// Tab toggles chat on a *single* press. The video surface when one is
  /// mounted, else the invisible root holder. Called on load-screen entry and
  /// whenever the chat collapses (chevron toggle AND drag-to-hide snap — the
  /// drag path used to skip this, which is why hiding-by-drag needed two Taps).
  void _restorePlayerFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_videoSurfaceMounted) {
        _videoFocus.requestFocus();
      } else {
        _rootFocus.requestFocus();
      }
    });
  }

  /// Play a preset on demand for the Settings preview. Bypasses the notify
  /// throttle so a preview always sounds, but reuses the same player.
  Future<void> _previewSound(String asset) async {
    try {
      await _audioPlayer.open(Media(asset), play: true);
    } catch (e) {
      debugPrint('Failed to preview sound: $e');
    }
  }
}

class _HomeScreenState extends _HomeScreenStateBase
    with
        _HomeIdleState,
        _HomeSyncState,
        _HomeChatState,
        _HomeMediaState,
        _HomeBody {
  /// Our registered window-close hook (announces a deliberate leave so peers see
  /// "left the room" not "lost connection" when the app is closed via the X
  /// rather than the Leave button — #92). Held so dispose only clears the global
  /// when it's still ours.
  Future<void> Function()? _closeHook;

  @override
  void initState() {
    super.initState();
    _initSettings();
    _onUserInteraction();
    // Restore the persisted corner into BOTH slots: we start collapsed, and
    // expanding restores lastCorner — corner alone would be discarded by the
    // first toggle.
    final corner = widget.initialCorner ?? ChatCorner.bottomLeft;
    _chatLayout = ChatOverlayLayout(
      // Start collapsed so the load screen stays clean (just a small chat tab in
      // the corner) instead of a big empty card crowding the load controls. Tab
      // — hinted on the load screen — expands it.
      collapsed: true,
      corner: corner,
      lastCorner: corner,
      widthPx: widget.initialWidthPx,
      heightPx: widget.initialHeightPx,
    );
    // Borrow the process-lifetime engines instead of creating per-room ones:
    // disposing a libmpv Player on leave can deadlock the UI thread on Windows
    // and permanently freeze the Connect screen (#137). See [VideoEnginePool].
    _core = VideoEnginePool.instance.videoCore;
    _session = SessionServices.forMode(
      mode: widget.config.sessionMode,
      video: _core,
      onLog: appLog,
      shouldLog: _shouldLog,
    );
    _chrome = SessionChrome.forMode(_session.mode);
    _audioPlayer = VideoEnginePool.instance.audioPlayer;
    // Playback-stop wake is local and synced: EOF after the controls fade
    // must show them again. Collaboration streams stay behind [_isSynced].
    _initPlaybackWakeSubscription();
    if (_isSynced) {
      // Hashed label, never the raw room: a private room's name is its access
      // code, so logging it verbatim would leak the room credential (#146 review).
      appLog('life: enter ${roomLogLabel(widget.config.room)}');
      // The stream wiring lives with its seam: chat/reaction/typing hookups in
      // [_HomeChatState], connection/presence/file/activity/roster hookups in
      // [_HomeSyncState]. Registration order is preserved from the pre-split
      // screen (#182).
      _initChatSubscriptions();
      _initSyncSubscriptions();
    } else {
      appLog('life: enter local session');
    }

    _username = widget.config.username;
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_saveResumePosition());
    });
    final resume = widget.config.resumeFilePath;
    if (resume != null) {
      // Restore the saved position before joining Syncplay. Connecting first
      // races the server's initial 0:00 state against the resume seek and can
      // make Continue Watching appear to start over.
      unawaited(
        _resumeForLaunch(
          resume,
          widget.config.resumePositionMs,
          connectAfterResume: _isSynced,
        ),
      );
    } else if (_isSynced) {
      unawaited(_connectExistingRoom());
    }
    // Landing on the load screen (no video yet): nudge the user that chat lives
    // behind Tab — a quick fading toast plus a pulse of the collapsed chat tab.
    // Skipped if we're resuming straight into a video, or in a local session
    // that has no chat.
    if (resume == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _core.state.fileName != null) return;
        // Give the invisible root holder focus so the FIRST Tab bubbles to the
        // chat toggle instead of being swallowed by default focus traversal —
        // otherwise the load screen needs two Tab presses to open chat.
        _rootFocus.requestFocus();
        if (_chrome.chatTabHint) _showChatTabHint();
      });
    }
  }

  Future<void> _initSettings() async {
    // Restore the chat card's persisted size + corner NOW, not from the
    // app-startup snapshot the constructor carries: that snapshot goes stale
    // the moment the user resizes/moves the card, so re-entering a room used
    // to reset the card. The card starts collapsed, so this async read always
    // lands before it is first shown.
    final sizeValue = await widget.settings.get(kChatCardSizeSettingKey);
    final cornerValue = await widget.settings.get(kChatCardCornerSettingKey);
    if (mounted) {
      setState(
        () => _chatLayout = restoredLayout(
          base: _chatLayout,
          sizeValue: sizeValue,
          cornerValue: cornerValue,
        ),
      );
    }
    await _loadLogLevel();
    final dimSetting = await widget.settings.get(kChatAutoDimSettingKey);
    if (dimSetting == 'false' && mounted) {
      setState(() => _chatAutoDim = false);
    }
    final wakeSetting = await widget.settings.get(
      kChatWakeOnNewMessageSettingKey,
    );
    if (wakeSetting == 'true' && mounted) {
      setState(() => _chatWakeOnMessage = true);
    }
    final dimSettingRaw = await widget.settings.get(kChatIdleDimSettingKey);
    final dim = double.tryParse(dimSettingRaw ?? '');
    if (dim != null && mounted) {
      setState(
        () => _chatIdleDim = dim.clamp(kChatIdleDimMin, kChatIdleDimMax),
      );
    }
    final primary = await widget.settings.get(kNotifyPrimarySoundKey);
    final secondary = await widget.settings.get(kNotifySecondarySoundKey);
    if (mounted) {
      setState(() {
        _primarySoundId = resolvePrimary(primary).id;
        _secondarySoundId = resolveSecondary(secondary).id;
      });
    }
    final historyMode = historyModeFromName(
      await widget.settings.get(kHistoryModeSettingKey),
    );
    if (mounted) setState(() => _historyMode = historyMode);
  }

  /// Read the persisted diagnostic-log level into [_logLevel] so the gear menu
  /// shows the right selection. The live log itself was already opened at this
  /// level in `main()` (#140) — this only mirrors it into the UI state.
  Future<void> _loadLogLevel() async {
    final level = logLevelFromName(
      await widget.settings.get(kLogLevelSettingKey),
    );
    if (mounted) setState(() => _logLevel = level);
  }

  Future<void> _connectExistingRoom() async {
    final sync = _sync;
    if (sync == null) return;
    _closeHook = () async {
      appLog('life: window-close hook fired (announcing leave)');
      await sync.disconnectForAppClose();
      appLog('life: window-close leave sent');
    };
    appCloseHook.value = _closeHook;
    await sync.connect(
      server: widget.config.server,
      port: widget.config.port,
      username: widget.config.username,
      room: widget.config.room,
      password: widget.config.password,
    );
  }

  /// Continue Watching launch coordinator. A synced session joins only after
  /// the saved seek has landed, so the server's initial room state cannot race
  /// the local resume back to 0:00. Local sessions simply resume and stop here.
  Future<void> _resumeForLaunch(
    String path,
    int positionMs, {
    required bool connectAfterResume,
  }) async {
    try {
      await _resume(path, positionMs);
    } finally {
      if (connectAfterResume && mounted && _isSynced) {
        await _connectExistingRoom();
      }
    }
  }

  /// Explicit in-player Local toggle: persist the lobby default AND switch
  /// this session's effective mode live. Join override never calls this.
  @override
  Future<void> _setEffectiveLocalMode(bool local) async {
    while (_modeSwitch != null) {
      await _modeSwitch;
      if (!mounted) return;
    }
    final done = Completer<void>();
    _modeSwitch = done.future;
    try {
      await _runEffectiveLocalMode(local);
    } finally {
      _modeSwitch = null;
      done.complete();
    }
  }

  Future<void> _runEffectiveLocalMode(bool local) async {
    if (local == _session.isLocal) {
      await _persistLocalPlayerMode(local);
      return;
    }
    await _saveResumePosition(force: true);
    if (local) {
      await _tearDownCollaboration();
    } else {
      await _startCollaboration();
    }
    await _persistLocalPlayerMode(local);
    final path = _core.state.filePath;
    if (path != null && isPlaybackOpen(_core.state)) {
      await _recordOpen(path);
      await _saveResumePosition(force: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _persistLocalPlayerMode(bool local) {
    return widget.settings.set(kLocalPlayerModeSettingKey, local.toString());
  }

  Future<void> _startCollaboration() async {
    _session.startSynced(
      video: _core,
      // The player is already open in a live switch, and the load coordinator
      // will not re-confirm this source to the new bridge (#252).
      openSource: _loadedSource,
      onLog: appLog,
      shouldLog: _shouldLog,
    );
    _chrome = SessionChrome.forMode(SessionMode.synced);
    _syncStatus = SyncConnectionStatus.connecting;
    _syncError = null;
    _initChatSubscriptions();
    _initSyncSubscriptions();
    unawaited(_connectExistingRoom());
    appLog('life: local → synced ${roomLogLabel(widget.config.room)}');
  }

  Future<void> _tearDownCollaboration() async {
    await _cancelCollaborationSubscriptions();
    _clearCollaborationUiState();
    if (identical(appCloseHook.value, _closeHook)) appCloseHook.value = null;
    _closeHook = null;
    await _session.stopToLocal();
    _chrome = SessionChrome.forMode(SessionMode.local);
    appLog('life: synced → local');
  }

  Future<void> _cancelCollaborationSubscriptions() async {
    await _chatSub?.cancel();
    await _reactionSub?.cancel();
    await _typingSub?.cancel();
    await _connSub?.cancel();
    await _presenceSub?.cancel();
    await _noticeSub?.cancel();
    await _peerFileSub?.cancel();
    await _activitySub?.cancel();
    await _rosterSub?.cancel();
    await _leavingSub?.cancel();
    await _activityThrottleSub?.cancel();
    _chatSub = null;
    _reactionSub = null;
    _typingSub = null;
    _connSub = null;
    _presenceSub = null;
    _noticeSub = null;
    _peerFileSub = null;
    _activitySub = null;
    _rosterSub = null;
    _leavingSub = null;
    _activityThrottleSub = null;
  }

  void _clearCollaborationUiState() {
    _syncStatus = SyncConnectionStatus.disconnected;
    _syncError = null;
    _peers.clear();
    _pendingGhosts.clear();
    _cleanlyLeaving.clear();
    _departedAt.clear();
    _lastConnectedUsername = null;
    _wasReconnecting = false;
    _prevSyncStatus = SyncConnectionStatus.disconnected;
    _peerFiles = const PeerFiles();
    _syncHealthy = false;
    _autoPausedNotice = false;
    _autoPausedReason = null;
    _autoPauseTimer?.cancel();
    _autoPauseTimer = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _presenceNotice.value = null;
    _lastPeerLeft = null;
    _joinPrompt = null;
    _activityThrottle.clearPending();
    _messages.value = const [];
    _typingLabel.value = null;
    _chatHasUnread.value = false;
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _typingUsers.clear();
    _chatHintToken = null;
  }

  @override
  void dispose() {
    appLog('life: dispose home (tearing down room)');
    // Invalidate any in-flight load so an async resolve/provision that is still
    // running (a page URL the user pasted right before leaving) abandons at its
    // next generation check instead of touching the now-disposed player or
    // writing the about-to-be-disposed _resolveNotice (Codex #223 P1/P2).
    _loadGeneration++;
    // Drop the window-close hook (only if it's still ours) so a closed room
    // doesn't keep preventing the OS fast-close path.
    if (identical(appCloseHook.value, _closeHook)) appCloseHook.value = null;
    _uiIdleTimer?.cancel();
    _uiDeepIdleTimer?.cancel();
    _historyTimer?.cancel();
    unawaited(_saveResumePosition(force: true));
    _peekTimer?.cancel();
    unawaited(_chatSub?.cancel());
    unawaited(_reactionSub?.cancel());
    unawaited(_typingSub?.cancel());
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    unawaited(_reactionFeed.close());
    unawaited(_connSub?.cancel());
    unawaited(_presenceSub?.cancel());
    unawaited(_noticeSub?.cancel());
    unawaited(_playbackWakeSub?.cancel());
    unawaited(_peerFileSub?.cancel());
    unawaited(_activitySub?.cancel());
    unawaited(_rosterSub?.cancel());
    unawaited(_leavingSub?.cancel());
    unawaited(_activityThrottleSub?.cancel());
    unawaited(_activityThrottle.dispose());
    _presenceTimer?.cancel();
    _autoPauseTimer?.cancel();
    // Notifier teardown: their timers and stream subscriptions are all
    // cancelled above, so nothing writes them after this point.
    _messages.dispose();
    _typingLabel.dispose();
    _peekPulsing.dispose();
    _chatHasUnread.dispose();
    _presenceNotice.dispose();
    _resolveNotice.dispose();
    unawaited(_session.dispose());
    // Reset, don't dispose: the engines are shared (process-lifetime) and a
    // libmpv dispose here can deadlock-freeze the next screen on Windows (#137).
    // The bridge above already cancelled its subscriptions to _core, and each
    // new room re-subscribes to the reused engine. See [VideoEnginePool].
    unawaited(_core.reset());
    unawaited(_audioPlayer.stop());
    // Flush, don't close: the session log is process-wide (#140) and the lobby
    // (and any next room) keep writing to it. Pushing buffered lines to disk
    // here means a freeze right after leaving still has this room's trace on
    // disk. The log is closed only on app exit (the window-close handler).
    unawaited(_syncLog?.flush() ?? Future<void>.value());
    _videoFocus.dispose();
    _rootFocus.dispose();
    // Synchronous exit checkpoint (#176). `_core.reset()` above is unawaited and
    // its `_player.stop()` is async (media_kit dispatches via mpv_command_async),
    // so reset() yields at `await stop()` and this line runs right after —
    // meaning the crash-markers sidecar normally reads `reset stop begin`,
    // `dispose home done`, then (once stop acks) `reset stop done`. So this
    // checkpoint marks only that dispose()'s SYNCHRONOUS body finished; it does
    // NOT imply the engine stopped. Read the tail by `reset stop done`, not this
    // line: `reset stop done` present ⇒ stop completed and any freeze is later
    // (post-dispose native render/raster teardown of the held frame); `reset stop
    // begin` with no `reset stop done` ⇒ wedged in/around libmpv `stop()`,
    // regardless of `dispose home done`. Written with appLogSync (not appLog)
    // because dispose() can't await and a queued async flush would never run if
    // the freeze lands in or right after super.dispose().
    appLogSync('life: dispose home done');
    super.dispose();
  }
}
