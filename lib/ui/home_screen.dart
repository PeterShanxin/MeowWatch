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
import '../core/data/settings_store.dart';
import '../core/data/stores.dart';
import '../core/debug/debug_log.dart';
import '../core/debug/log_archive.dart';
import '../core/debug/log_level.dart';
import '../core/sync/auto_pause.dart';
import '../core/sync/file_match.dart';
import '../core/sync/join_prompt.dart';
import '../core/sync/loaded_file_message.dart';
import '../core/sync/presence_messages.dart';
import '../core/sync/room_greeting.dart';
import '../core/sync/peer_files.dart';
import '../core/sync/peer_state.dart';
import '../core/sync/playback_sync_bridge.dart';
import '../core/sync/sync_activity_throttle.dart';
import '../core/sync/syncplay_client.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import '../core/theme/tokens/motion.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/video/media_kit_video_core.dart';
import '../core/video/await_open_result.dart';
import '../core/video/playback_state.dart';
import '../core/video/seek_when_ready.dart';
import '../core/video/source_announce.dart';
import '../core/video/video_url.dart';
import 'app_close_hook.dart';
import 'chat/chat_overlay.dart';
import 'chat/chat_overlay_layout.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'idle_visibility.dart';
import 'notify_decision.dart';
import 'paste_link_dialog.dart';
import 'player_menu_button.dart';
import 'reactions/floating_reactions.dart';
import 'reactions/reaction_bar.dart';
import 'sync_activity_text.dart';
import 'video_error_state.dart';
import 'video_surface.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.config,
    required this.history,
    required this.settings,
    required this.currentTheme,
    required this.onThemeChanged,
    this.initialWidthPx,
    this.initialHeightPx,
    super.key,
  });

  final RoomConfig config;
  final HistoryStore history;
  final SettingsStore settings;
  final double? initialWidthPx;
  final double? initialHeightPx;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MediaKitVideoCore _core;
  late final SyncplayClient _sync;
  late final PlaybackSyncBridge _bridge;

  /// Rotating diagnostic log. Built once the app-support dir resolves in
  /// [_initSettings] (path_provider is async), so it's null at first; [_log]
  /// forwards safely and early startup lines are simply dropped. Captures the
  /// Syncplay trace persistently so the intermittent co-watch A/V lag is on
  /// disk the next time it strikes.
  DebugLog? _syncLog;
  LogLevel _logLevel = LogLevel.verbose;
  late final Player _audioPlayer;

  /// Lines emitted before the async [_initSyncLog] installs [_syncLog] — the
  /// connection handshake and any fast early failures. Held here and replayed
  /// into the logger once it exists, so startup problems aren't silently
  /// dropped. Capped so a stuck init can't grow it without bound.
  final List<String> _pendingLog = <String>[];
  static const int _maxPendingLog = 1000;

  /// Stable sink handed to [SyncplayClient] before [_syncLog] exists, so the
  /// client never holds a dangling closure and all traffic lands in one place.
  void _log(String line) {
    final log = _syncLog;
    if (log != null) {
      log(line);
    } else if (_pendingLog.length < _maxPendingLog) {
      _pendingLog.add(line);
    }
  }

  // Notification chime: bundled assets (portable, no dependency on a
  // system-specific sound file), throttled so a burst of messages doesn't
  // stack overlapping playbacks. Which preset plays is chosen in Settings and
  // resolved via [resolvePrimary]/[resolveSecondary].
  static const Duration _notifyThrottle = Duration(seconds: 2);
  final Stopwatch _notifyClock = Stopwatch();

  SyncConnectionStatus _syncStatus = SyncConnectionStatus.disconnected;
  String? _syncError;
  final Set<String> _peers = <String>{};
  StreamSubscription<SyncConnectionState>? _connSub;
  StreamSubscription<PresenceEvent>? _presenceSub;
  StreamSubscription<PlaybackState>? _noticeSub;
  StreamSubscription<PeerFile>? _peerFileSub;
  StreamSubscription<SyncActivity>? _activitySub;
  StreamSubscription<List<String>>? _rosterSub;
  StreamSubscription<String>? _leavingSub;

  /// Our registered window-close hook (announces a deliberate leave so peers see
  /// "left the room" not "lost connection" when the app is closed via the X
  /// rather than the Leave button — #92). Held so dispose only clears the global
  /// when it's still ours.
  Future<void> Function()? _closeHook;

  /// Previous connection status — used to detect the drop edge.
  SyncConnectionStatus _prevSyncStatus = SyncConnectionStatus.disconnected;

  /// Latched true on a local drop (connected → reconnecting) and cleared when we
  /// reconnect or stop trying. Needed because the reconnect path passes through
  /// an intermediate `handshaking` state, so the "Reconnected to room." line
  /// can't be detected from `prev` alone (issue #92).
  bool _wasReconnecting = false;

  /// Peers who sent a [LeavingSignal] before their [PresenceKind.left] event;
  /// consumed once on departure to determine clean vs. connection-drop wording.
  final Set<String> _cleanlyLeaving = <String>{};

  /// When each peer last departed, so a quick rejoin reads as "reconnected"
  /// rather than "joined the room" (issue #92).
  final Map<String, DateTime> _departedAt = <String, DateTime>{};

  /// Files announced by peers, keyed by username, plus our own loaded file's
  /// byte size — together they drive the file-mismatch warning. Keying by user
  /// (rather than a single slot) means a transient ghost of our own dropped
  /// session can't wipe a real friend's file when it departs (#93). [_peerFile]
  /// surfaces only a currently-present peer's file.
  PeerFiles _peerFiles = const PeerFiles();
  int? _localFileSizeBytes;

  /// The file of the peer we're currently watching with, or null if no present
  /// peer has announced one. Derived from [_peerFiles] restricted to [_peers].
  PeerFile? get _peerFile => _peerFiles.currentAmong(_peers);

  /// Was the session in sync (connected + a peer present) at the last check?
  /// Used to detect the healthy -> unhealthy edge that triggers auto-pause.
  bool _syncHealthy = false;

  /// True while we've auto-paused because sync dropped; drives the banner.
  bool _autoPausedNotice = false;

  /// The reason text for the current auto-pause (peer left vs. connection lost),
  /// snapshotted at pause time so the banner can't later show a stale cause.
  String? _autoPausedReason;

  /// Transient banner when a friend joins/rejoins the room (auto-clears).
  String? _presenceNotice;
  Timer? _presenceTimer;

  /// The name of the last peer who left the room.
  String? _lastPeerLeft;

  /// Persistent "your friend started playback — load a video to join" prompt
  /// shown on the empty (no-video) screen when a peer controls playback before
  /// we've loaded anything (#60). Cleared once we load a video or the peer
  /// leaves. The reverse direction is handled by the same code running on the
  /// friend's machine.
  String? _joinPrompt;

  /// Debounce before auto-pausing: a brief blip (e.g. a heartbeat timeout that
  /// recovers a second later, common when two instances share one PC) should
  /// NOT pause — only a sustained loss of sync.
  Timer? _autoPauseTimer;
  static const _autoPauseDelay = Duration(seconds: 2);

  late final ChatStore _chat;
  late ChatOverlayLayout _chatLayout;
  bool _chatDragging = false;

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
  List<ChatMessage> _messages = const <ChatMessage>[];
  late String _username;
  bool _peekPulsing = false;
  Timer? _peekTimer;
  Timer? _historyTimer;
  StreamSubscription<List<ChatMessage>>? _chatSub;
  StreamSubscription<ReactionEvent>? _reactionSub;
  StreamSubscription<TypingEvent>? _typingSub;

  /// Feeds the floating-reactions overlay. Both our own and peers' reactions
  /// flow through here (via the chat echo) so everyone sees the same burst.
  final StreamController<String> _reactionFeed =
      StreamController<String>.broadcast();

  /// Peers currently typing, each with a watchdog timer that clears them if a
  /// "stopped" signal is lost.
  final Set<String> _typingUsers = <String>{};
  final Map<String, Timer> _typingTimers = <String, Timer>{};

  bool _isUiIdle = false;
  Timer? _uiIdleTimer;

  /// Second idle stage: after staying idle past the first threshold, the dimmed
  /// chat card fades fully out (issue #34) instead of lingering as a ghost.
  bool _isUiDeepIdle = false;
  Timer? _uiDeepIdleTimer;
  static const _uiIdleDelay = Duration(seconds: 3);
  static const _uiDeepIdleDelay = Duration(seconds: 3);

  bool _chatAutoDim = true;
  bool _chatHasUnread = false;
  bool _chatWakeOnMessage = false;
  double _chatIdleDim = kChatIdleGhostOpacity;
  String _primarySoundId = kDefaultPrimarySoundId;
  String _secondarySoundId = kDefaultSecondarySoundId;

  /// Collapses bursts of seek notifications into a single line/banner (#26).
  final SyncActivityThrottle _activityThrottle = SyncActivityThrottle();
  StreamSubscription<SyncActivity>? _activityThrottleSub;

  @override
  void initState() {
    super.initState();
    _initSettings();
    _onUserInteraction();
    _chatLayout = ChatOverlayLayout(
      widthPx: widget.initialWidthPx,
      heightPx: widget.initialHeightPx,
    );
    _core = MediaKitVideoCore();
    _sync = SyncplayClient(onLog: _log);
    _bridge = PlaybackSyncBridge(video: _core, sync: _sync)..start();
    _chat = ChatStore(sync: _sync);
    _audioPlayer = Player();
    _chatSub = _chat.stream.listen((msgs) async {
      if (!mounted) return;
      final newCount = msgs.length - _messages.length;
      final isNewMessage = newCount > 0;
      final lastMsg = isNewMessage ? msgs.last : null;

      setState(() => _messages = msgs);

      if (_chatLayout.collapsed && isNewMessage) _pulsePeek();

      if (isNewMessage && lastMsg != null && lastMsg.username != _username) {
        // Real peer chat (not a system/sync line) wakes the dimmed card, which
        // then settles back out — so a brighten never lingers forever.
        if (!lastMsg.system) _wakeChatThenReArmDeepIdle();

        final focused = await windowManager.isFocused();
        if (!mounted) return;
        final kind = decideNotify(
          isSystem: lastMsg.system,
          isOwnMessage: lastMsg.username == _username,
          windowFocused: focused,
          chatCollapsed: _chatLayout.collapsed,
          // An expanded card the user can't read either: idle has faded it to
          // the dim ghost. `chatDimmedByIdle` defers to `chatOverlayOpacity`
          // for what's actually on screen — auto-dim off, or the wake-on-message
          // setting, keep the card fully visible, so those stay silent.
          chatDimmedByIdle: chatDimmedByIdle(
            idle: _isUiIdle,
            collapsed: _chatLayout.collapsed,
            autoDim: _chatAutoDim,
            wakeToFullyVisible: _chatWakeOnMessage,
          ),
          videoPlaying: _core.state.status == PlaybackStatus.playing,
        );
        if (kind == NotifyKind.none) return;
        if (_notifyClock.isRunning && _notifyClock.elapsed < _notifyThrottle) {
          return;
        }
        _notifyClock
          ..reset()
          ..start();
        final asset = kind == NotifyKind.primary
            ? resolvePrimary(_primarySoundId).asset
            : resolveSecondary(_secondarySoundId).asset;
        try {
          await _audioPlayer.open(Media(asset), play: true);
        } catch (e) {
          debugPrint('Failed to play notification: $e');
        }
      }
    });
    _reactionSub = _chat.reactions.listen((e) {
      if (mounted && !_reactionFeed.isClosed) _reactionFeed.add(e.emoji);
    });
    _typingSub = _chat.typing.listen(_onTyping);
    _connSub = _sync.connectionState.listen((s) {
      if (mounted) {
        setState(() {
          _syncStatus = s.status;
          _syncError = s.message;
          // Adopt the server-assigned wire identity so chat ownership, typing
          // attribution and self-notifications all match the name peers (and the
          // chat echo) actually use for us (#40). This is the WIRE name only — it
          // can carry a transient dedupe suffix after a reconnect, so the gear
          // member list shows widget.config.username (our chosen name) instead (#107).
          if (s.username != null && s.username!.isNotEmpty) {
            _username = s.username!;
          }
          if (s.status != SyncConnectionStatus.connected) {
            // Our own connection changed — peer membership and the per-peer
            // departure/leaving bookkeeping are no longer valid. Clearing here
            // also bounds these maps across repeated local reconnect cycles.
            _peers.clear();
            _departedAt.clear();
            _cleanlyLeaving.clear();
            // Drop the cached peer files too, so they are rebuilt
            // deterministically from the post-reconnect roster rather than
            // masking a stale value (#93). _peerNoVideoHint is gated on
            // _syncHealthyNow, so this can't flash "hasn't loaded" while
            // we're disconnected.
            _peerFiles = const PeerFiles();
            // The empty-screen join prompt is pinned imperatively from peer
            // file/playback events, so it isn't gated on sync health like the
            // banner is. Clear it here too, or a "<peer> loaded …" / "started
            // playback …" nudge stays on the load screen with no peer present
            // while we reconnect or disconnect (#116 review).
            _joinPrompt = null;
          }
          _evaluateSyncHealth();
        });
      }
      // Local connection transition chat lines (issue #92). Run after setState
      // so _syncStatus is already updated; addSystem pushes its own emission.
      if (isConnectionDrop(prev: _prevSyncStatus, next: s.status)) {
        _wasReconnecting = true;
        _chat.addSystem(connectionLostMessage);
      } else if (isReconnectSuccess(
        wasReconnecting: _wasReconnecting,
        next: s.status,
      )) {
        _wasReconnecting = false;
        _chat.addSystem(reconnectedToRoomMessage);
      }
      // A deliberate leave or fatal error ends the reconnect attempt — drop the
      // latch so a later fresh connect isn't mistaken for a reconnect.
      if (s.status == SyncConnectionStatus.disconnected ||
          s.status == SyncConnectionStatus.error) {
        _wasReconnecting = false;
      }
      _prevSyncStatus = s.status;
      if (s.status == SyncConnectionStatus.connected &&
          _shouldReannounceOnConnect()) {
        unawaited(_announceCurrentFile());
      }
    });
    // Track peers who announced a deliberate leave so the presence listener can
    // distinguish "left the room" from "lost connection" (issue #92).
    _leavingSub = _chat.leaving.listen((name) => _cleanlyLeaving.add(name));
    _presenceSub = _sync.presence.listen((e) {
      if (!mounted) return;
      setState(() {
        if (e.kind == PresenceKind.joined) {
          final isNew = _peers.add(e.username);
          // Roster entries (people already here when we arrived) update
          // membership silently; only a live join gets a banner + event line.
          if (isNew && !e.fromRoster) {
            final reconnected = isPeerReconnect(
              departedAt: _departedAt[e.username],
              now: DateTime.now(),
            );
            _departedAt.remove(e.username);
            final banner = reconnected
                ? '🐾 ${e.username} reconnected'
                : '🐾 ${e.username} joined';
            _showTransientNotice(banner);
            _chat.addSystem(
              peerJoinMessage(username: e.username, reconnected: reconnected),
            );
          }
        } else {
          _peers.remove(e.username);
          _lastPeerLeft = e.username;
          _peerFiles = _peerFiles.remove(e.username);
          // The "load a video to join" prompt is stale once they've left (#60).
          _joinPrompt = null;
          final clean = _cleanlyLeaving.remove(e.username);
          // Only a *drop* makes a quick return read as "reconnected"; a
          // deliberate leave that comes back is a fresh "joined", not a network
          // blip recovering (#92 follow-up).
          if (clean) {
            _departedAt.remove(e.username);
          } else {
            _departedAt[e.username] = DateTime.now();
          }
          final banner = clean
              ? '👋 ${e.username} left'
              : '📵 ${e.username} lost connection';
          _showTransientNotice(banner);
          _chat.addSystem(
            peerDepartureMessage(username: e.username, clean: clean),
          );
        }
        _evaluateSyncHealth();
      });
    });
    _peerFileSub = _sync.peerFile.listen((f) {
      if (!mounted) return;
      setState(() {
        _peerFiles = _peerFiles.set(f);
        // A peer announced a loaded file while we have nothing loaded: pin the
        // "load the same video to join" prompt on the empty screen so the side
        // still picking a file knows which one — the mirror of the loader's
        // "hasn't loaded a video yet" heads-up (#116). The play-triggered prompt
        // below takes over if/when they actually start playback.
        final prompt = peerLoadedJoinPrompt(
          localHasFile: _core.state.fileName != null,
          localUsername: _username,
          peerUsername: f.username,
          // Show the short/redacted label — a peer's raw URL (with any signed
          // token) must never render verbatim in our join prompt.
          peerFileName: mediaDisplayName(f.name),
        );
        if (prompt != null) _joinPrompt = prompt;
      });
    });
    // Sync activities (peer + our own) flow through the throttle so a scrub
    // burst collapses to one line/banner (#26); the throttled output drives the
    // banner + chat history. We gate on sync health at BOTH ends: at intake to
    // avoid buffering lonely activity, and again at output because the throttle
    // debounce can outlast a peer leaving — without the second gate, an activity
    // queued while healthy would still surface after sync is gone (#41).
    _activitySub = _sync.activity.listen((a) {
      if (!_syncHealthyNow) return;
      _activityThrottle.add(a);
    });
    _activityThrottleSub = _activityThrottle.stream.listen((a) {
      if (!mounted || !_syncHealthyNow) return;
      final t = syncActivityText(a, selfUsername: _username);
      setState(() {
        _showTransientNotice(t.banner);
        // A peer drove playback while we have no video loaded: the transient
        // banner is easy to miss on the empty screen, so also pin a persistent
        // "load a video to join" prompt there (#60).
        final prompt = peerStartedPlaybackJoinPrompt(
          localHasFile: _core.state.fileName != null,
          localUsername: _username,
          peerUsername: a.username,
        );
        if (prompt != null) _joinPrompt = prompt;
      });
      _chat.addSystem(t.chatLine);
    });
    _rosterSub = _sync.initialRoster.listen((members) {
      if (mounted) _chat.addSystem(roomGreeting(members));
    });
    _noticeSub = _core.stateStream.listen((s) {
      if (!mounted) return;
      if (_autoPausedNotice && s.status == PlaybackStatus.playing) {
        setState(() => _autoPausedNotice = false);
      }
      if ((_isUiIdle || _isUiDeepIdle) && s.status != PlaybackStatus.playing) {
        _uiDeepIdleTimer?.cancel();
        setState(() {
          _isUiIdle = false;
          _isUiDeepIdle = false;
        });
      }
    });

    _username = widget.config.username;
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_saveResumePosition());
    });
    unawaited(
      _sync.connect(
        server: widget.config.server,
        port: widget.config.port,
        username: widget.config.username,
        room: widget.config.room,
        password: widget.config.password,
      ),
    );
    // Announce a deliberate leave if the window is closed (X button) while we're
    // in the room — disconnect() sends the leaving signal with a bounded flush
    // (#92). The Leave button already does this directly via _leave().
    _closeHook = () => _sync.disconnect();
    appCloseHook.value = _closeHook;
    final resume = widget.config.resumeFilePath;
    if (resume != null) {
      unawaited(_resume(resume, widget.config.resumePositionMs));
    }
  }

  Future<void> _initSettings() async {
    await _initSyncLog();
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
  }

  /// Build the rotating diagnostic log in a stable app dir and start it at the
  /// persisted level (default verbose). Guarded end-to-end so a missing dir or
  /// platform plugin can never block playback startup.
  Future<void> _initSyncLog() async {
    final level = logLevelFromName(
      await widget.settings.get(kLogLevelSettingKey),
    );
    DebugLog? log;
    try {
      final logsDir = await resolveAppLogsDir();
      log = DebugLog.inDir(logsDir, baseName: 'meowwatch_sync', level: level)
        ..start();
    } on Object {
      log = null; // No log dir available — diagnostics off, app unaffected.
    }
    if (!mounted) {
      await log?.close();
      return;
    }
    if (log != null) {
      // Replay lines captured before the logger existed (handshake / early
      // failures). They take the replay timestamp rather than the original,
      // but that's within a few ms — and the alternative is losing them.
      for (final line in _pendingLog) {
        log(line);
      }
    }
    _pendingLog.clear();
    setState(() {
      _syncLog = log;
      _logLevel = level;
    });
  }

  /// Apply a new diagnostic-log level live and persist it.
  void _onLogLevelChanged(LogLevel level) {
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
    final zipBytes = zipLogFiles(dir);
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

  void _onUserInteraction() {
    if (_isUiIdle || _isUiDeepIdle) {
      setState(() {
        _isUiIdle = false;
        _isUiDeepIdle = false;
      });
    }
    _uiIdleTimer?.cancel();
    _uiDeepIdleTimer?.cancel();
    _uiIdleTimer = Timer(_uiIdleDelay, () {
      if (!mounted || _core.state.status != PlaybackStatus.playing) return;
      setState(() => _isUiIdle = true);
      // Stage two: once idle persists, fully hide the dimmed chat card (#34).
      _uiDeepIdleTimer = Timer(_uiDeepIdleDelay, _enterDeepIdle);
    });
  }

  void _enterDeepIdle() {
    if (!mounted || _core.state.status != PlaybackStatus.playing) return;
    setState(() => _isUiDeepIdle = true);
  }

  /// A fresh peer message during idle should wake the dimmed chat and then let
  /// it settle out again, instead of lingering on screen forever. Drop deep
  /// idle so the card brightens (ghost, or full per the wake setting) and
  /// restart the deep-idle countdown so it fades back out if ignored. We keep
  /// `_isUiIdle` as-is — only the chat wakes, the controls/gear stay hidden.
  void _wakeChatThenReArmDeepIdle() {
    if (!_isUiIdle) return;
    _uiDeepIdleTimer?.cancel();
    if (_isUiDeepIdle) setState(() => _isUiDeepIdle = false);
    _uiDeepIdleTimer = Timer(_uiDeepIdleDelay, _enterDeepIdle);
  }

  @override
  void dispose() {
    // Drop the window-close hook (only if it's still ours) so a closed room
    // doesn't keep preventing the OS fast-close path.
    if (identical(appCloseHook.value, _closeHook)) appCloseHook.value = null;
    _uiIdleTimer?.cancel();
    _uiDeepIdleTimer?.cancel();
    _historyTimer?.cancel();
    unawaited(_saveResumePosition());
    _peekTimer?.cancel();
    unawaited(_chatSub?.cancel());
    unawaited(_reactionSub?.cancel());
    unawaited(_typingSub?.cancel());
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    unawaited(_reactionFeed.close());
    unawaited(_chat.dispose());
    unawaited(_connSub?.cancel());
    unawaited(_presenceSub?.cancel());
    unawaited(_noticeSub?.cancel());
    unawaited(_peerFileSub?.cancel());
    unawaited(_activitySub?.cancel());
    unawaited(_rosterSub?.cancel());
    unawaited(_leavingSub?.cancel());
    unawaited(_activityThrottleSub?.cancel());
    unawaited(_activityThrottle.dispose());
    _presenceTimer?.cancel();
    _autoPauseTimer?.cancel();
    unawaited(_bridge.dispose());
    unawaited(_sync.dispose());
    unawaited(_core.dispose());
    unawaited(_audioPlayer.dispose());
    unawaited(_syncLog?.close() ?? Future<void>.value());
    _videoFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  /// Track a peer's typing state (ignoring our own echoed signal). A 5s
  /// watchdog clears them in case the "stopped" signal is dropped.
  void _onTyping(TypingEvent e) {
    if (!mounted || e.username == _username) return;
    // A peer who wasn't typing now is — brighten the collapsed tab the same as
    // a fresh message would, so typing is noticeable without expanding (#53).
    final newlyTyping = e.isTyping && !_typingUsers.contains(e.username);
    setState(() {
      _typingTimers[e.username]?.cancel();
      _typingTimers.remove(e.username);
      if (e.isTyping) {
        _typingUsers.add(e.username);
        _typingTimers[e.username] = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          setState(() {
            _typingUsers.remove(e.username);
            _typingTimers.remove(e.username);
          });
        });
      } else {
        _typingUsers.remove(e.username);
      }
    });
    if (newlyTyping && _chatLayout.collapsed) _pulsePeek();
  }

  /// "lin is typing…" / "2 people are typing…", or null when nobody is.
  String? get _typingLabel {
    if (_typingUsers.isEmpty) return null;
    if (_typingUsers.length == 1) return '${_typingUsers.first} is typing…';
    return '${_typingUsers.length} people are typing…';
  }

  /// Toggle the chat card. When it collapses we restore focus to the player so
  /// the keyboard shortcut (Tab) and space/arrows keep working on one press.
  void _toggleChat() {
    setState(() => _chatLayout = _chatLayout.toggle());
    if (_chatLayout.collapsed) _restorePlayerFocus();
  }

  /// Hand keyboard focus back to a focused descendant after the chat collapses
  /// (which removes its auto-focused text field). The video surface when one is
  /// loaded, else the invisible root holder — either way the top-level Tab
  /// handler always has a focused node to bubble from, so Tab toggles on a
  /// single press. Called from BOTH the chevron toggle and the drag-to-hide
  /// snap — the drag path used to skip this, which is why hiding-by-drag then
  /// needed two Tab presses.
  void _restorePlayerFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_core.state.fileName != null) {
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

  void _pulsePeek() {
    setState(() => _peekPulsing = true);
    _peekTimer?.cancel();
    _peekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _peekPulsing = false);
    });
  }

  /// Show a transient banner (friend joined/left, or a sync action); auto-clears
  /// after a few seconds. Call inside setState.
  void _showTransientNotice(String text) {
    _presenceNotice = text;
    _presenceTimer?.cancel();
    _presenceTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _presenceNotice = null);
    });
  }

  bool get _syncHealthyNow => SyncHealth(
    connected: _syncStatus == SyncConnectionStatus.connected,
    hasPeer: _peers.isNotEmpty,
  ).healthy;

  /// Recompute sync health and (after a debounce) auto-pause on a sustained
  /// healthy -> unhealthy drop. Call inside setState after [_syncStatus] /
  /// [_peers] change.
  void _evaluateSyncHealth() {
    final nowHealthy = _syncHealthyNow;
    final isPlaying = _core.state.status == PlaybackStatus.playing;

    if (nowHealthy) {
      // Recovered (or never lost) — cancel any pending pause, clear banner.
      // Also forget who last left: keeping it would let a later *connection*
      // drop wrongly blame a friend who left a different session ago.
      _autoPauseTimer?.cancel();
      _autoPauseTimer = null;
      _autoPausedNotice = false;
      _lastPeerLeft = null;
    } else if (decideAutoPause(
          wasHealthy: _syncHealthy,
          nowHealthy: nowHealthy,
          isPlaying: isPlaying,
        ) &&
        _autoPauseTimer == null) {
      // Edge into unhealthy while playing — arm the debounce, confirm later.
      _autoPauseTimer = Timer(_autoPauseDelay, _confirmAutoPause);
    }
    _syncHealthy = nowHealthy;
  }

  /// Fires after the debounce: pause only if sync is STILL down and we're
  /// still playing. A blip that already recovered cancelled this timer.
  void _confirmAutoPause() {
    _autoPauseTimer = null;
    if (!mounted) return;
    final stillDown = !_syncHealthyNow;
    final playing = _core.state.status == PlaybackStatus.playing;
    if (stillDown && playing) {
      // Phrase the reason by actual cause: a friend leaving (still connected,
      // empty room) names them; any other drop is a connection loss and must
      // not claim someone left (#41 follow-up).
      final reason = autoPauseMessage(
        cause: autoPauseCause(
          connected: _syncStatus == SyncConnectionStatus.connected,
          hasPeer: _peers.isNotEmpty,
        ),
        peerName: _lastPeerLeft,
      );
      unawaited(_core.pause());
      setState(() {
        _autoPausedNotice = true;
        _autoPausedReason = reason;
      });
      _chat.addSystem(reason);
    }
  }

  /// Banner text shown over the video, or null when nothing to say. Priority:
  /// a fresh "friend joined" notice, then a file-mismatch warning, then the
  /// auto-pause reason, then a "friend hasn't loaded a video" heads-up, then the
  /// plain waiting/connect hint.
  String? get _banner {
    if (_presenceNotice != null) return _presenceNotice;
    final mismatch = _fileMismatchBanner;
    if (mismatch != null) return mismatch;
    if (_autoPausedNotice) {
      return '⏸ ${_autoPausedReason ?? 'Paused — lost sync with your friend'}';
    }
    final waitingForPeerVideo = _peerNoVideoHint;
    if (waitingForPeerVideo != null) return waitingForPeerVideo;
    return _syncHint;
  }

  /// The flip side of the empty-screen join prompt (#60): once WE have a video
  /// loaded and a friend is in the room but hasn't loaded one yet (no announced
  /// peer file), tell us they can't follow along until they load it — so a
  /// one-sided session isn't silent on our end either.
  String? get _peerNoVideoHint {
    if (_core.state.fileName == null) return null; // their concern, not ours
    if (!_syncHealthyNow) return null; // need a connected friend present
    if (_peerFile != null) return null; // they've announced a file
    final peer = _peers.isNotEmpty ? _peers.first : null;
    if (peer == null) return null;
    return '⏳ $peer hasn\'t loaded a video yet';
  }

  /// Warn when the peer's loaded file clearly differs from ours.
  String? get _fileMismatchBanner {
    final peer = _peerFile;
    if (peer == null) return null;
    final result = compareFiles(
      localName: _core.state.fileName,
      localSize: _localFileSizeBytes,
      peerName: peer.name,
      peerSize: peer.sizeBytes,
    );
    if (result != FileMatch.mismatch) return null;
    // Match on the raw name above; show the short/redacted label in the banner.
    return '⚠ Different file — ${peer.username} has "${mediaDisplayName(peer.name)}"';
  }

  /// Advisory hint shown over the video, or null when everything is ready.
  /// Reflects the live connection status (so the user sees "Connecting to room
  /// X…" instead of a generic prompt while the socket is still negotiating).
  String? get _syncHint {
    final room = widget.config.room;
    switch (_syncStatus) {
      case SyncConnectionStatus.connecting:
      case SyncConnectionStatus.handshaking:
        return 'Connecting to room $room…';
      case SyncConnectionStatus.reconnecting:
        // Surface the concrete failure reason when we have one (e.g. "Could not
        // reach server…" from a failed dial); otherwise the generic line.
        return _syncError != null
            ? '${_syncError!} — reconnecting…'
            : 'Connection lost — reconnecting to room $room…';
      case SyncConnectionStatus.error:
        return _syncError ?? 'Couldn\'t connect to room $room';
      case SyncConnectionStatus.disconnected:
        return 'Disconnected from room $room';
      case SyncConnectionStatus.connected:
        if (_peers.isEmpty) return 'Waiting for a friend to join…';
        return null;
    }
  }

  /// Load (but do not auto-play). In a room, hitting play yourself starts both
  /// of you in sync; auto-playing on load made the two clients fight at 0.
  Future<void> _load(String path) async {
    // We now have a video, so the "load a video to join" prompt is moot (#60).
    if (_joinPrompt != null && mounted) setState(() => _joinPrompt = null);
    await _core.load(path);
    // A source can fail asynchronously — mpv reports an unreachable / non-video
    // / expired URL, *and* a moved or unreadable local file, on its error stream
    // after load() returns. Don't record it to history, announce it to the room,
    // or post a "Loaded …" chat line until it actually opens, or a failed source
    // would surface to peers and history as loaded while we show the error
    // screen. Applies to local files too, not just URLs.
    if (!await awaitOpenResult(_core)) return;
    // Browse / Paste / drop stay reachable, so a newer load may have superseded
    // this one while we awaited — the core now describes that other source. Bail
    // rather than record/announce this stale path against it.
    if (!mounted || _core.state.filePath != path) return;
    await _recordOpen(path);
    await _announceCurrentFile();
    _addLoadedFileMessage();
  }

  /// Append a "Loaded …" system line to chat. Shows "in sync!" when the peer's
  /// file matches ours; otherwise just names the file. Replaces the misleading
  /// "jumped to 00:00" that appeared on first load (#91).
  void _addLoadedFileMessage() {
    final fileName = _core.state.fileName;
    if (fileName == null) return;
    final match = compareFiles(
      localName: fileName,
      localSize: _localFileSizeBytes,
      peerName: _peerFile?.name,
      peerSize: _peerFile?.sizeBytes,
    );
    // Match on the full name (URL identity); show the short label in chat.
    _chat.addSystem(
      loadedFileMessage(fileName: mediaDisplayName(fileName), match: match),
    );
  }

  Future<void> _resume(String path, int positionMs) async {
    await _load(path);
    await seekWhenReady(_core, Duration(milliseconds: positionMs));
  }

  Future<void> _recordOpen(String path) async {
    final state = _core.state;
    // A stream URL has no byte size — don't stat it as a file (the URL isn't a
    // valid path, and on Windows the ':' would throw a different error).
    final size = isHttpUrl(path) ? 0 : await _fileSize(path);
    if (mounted) setState(() => _localFileSizeBytes = size);
    await widget.history.recordOpen(
      filePath: path,
      fileName: state.fileName ?? path,
      fileSizeBytes: size,
      durationMs: state.duration.inMilliseconds,
      room: widget.config.room,
      username: widget.config.username,
    );
  }

  Future<void> _saveResumePosition() async {
    final state = _core.state;
    final path = state.filePath;
    if (path == null) return;
    // Only persist a resume point for a source that actually opened. A failed or
    // still-loading load leaves filePath set at position 0 (e.g. an expired URL
    // or a moved local file retried from history), and saving that would erase
    // the real saved position for that history row.
    if (!isPlaybackOpen(state)) return;
    await widget.history.updatePosition(
      filePath: path,
      positionMs: state.position.inMilliseconds,
      durationMs: state.duration.inMilliseconds,
    );
  }

  Future<void> _leave() async {
    _historyTimer?.cancel();
    await _saveResumePosition();
    await _sync.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  /// Whether the just-(re)connected room should be told about the current
  /// source — see [canAnnounceOnConnect] for the rule.
  bool _shouldReannounceOnConnect() => canAnnounceOnConnect(_core.state);

  Future<void> _announceCurrentFile() async {
    final state = _core.state;
    final path = state.filePath;
    if (path == null) return;
    // For a URL, size is unknown (streams have no byte length) and the URL
    // itself is the name we share — matching official Syncplay.
    final size = isHttpUrl(path) ? 0 : await _fileSize(path);
    _sync.announceFile(
      name: state.fileName ?? path,
      size: size,
      duration: state.duration,
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
    final typeGroup = XTypeGroup(
      label: 'Video',
      extensions: videoExtensions.toList(),
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await _load(file.path);
    }
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

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Scaffold(
      backgroundColor: m.background,
      // A non-focusable ancestor handler: it must NOT autofocus, or it
      // would steal primary focus from VideoSurface and kill its
      // space/arrow keys. Tab still reaches it by bubbling up from the
      // focused video surface, and skipTraversal stops the framework's
      // default Tab focus-traversal from swallowing it first.
      body: Focus(
        // Holds focus only when no VideoSurface is mounted (empty/waiting
        // screen) so the Tab handler always has a focused descendant. Never
        // autofocuses, so it won't steal the video's space/arrow keys.
        focusNode: _rootFocus,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          _onUserInteraction();
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            _toggleChat();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerDown: (_) => _onUserInteraction(),
          onPointerMove: (_) => _onUserInteraction(),
          onPointerUp: (_) => _onUserInteraction(),
          onPointerHover: (_) => _onUserInteraction(),
          onPointerSignal: (_) => _onUserInteraction(),
          child: VideoDropTarget(
            onFileDropped: _handleDropped,
            child: StreamBuilder<PlaybackState>(
              stream: _core.stateStream,
              initialData: _core.state,
              builder: (context, snapshot) {
                final state = snapshot.data!;
                // True only while a video surface is actually on screen — not on
                // the empty/load screen, and not on the load-error screen.
                final videoVisible = state.fileName != null &&
                    state.status != PlaybackStatus.error;
                final hint = _banner;
                final chatOpacity = chatOverlayOpacity(
                  idle: _isUiIdle,
                  deepIdle: _isUiDeepIdle,
                  collapsed: _chatLayout.collapsed,
                  autoDim: _chatAutoDim,
                  hasUnread: _chatHasUnread,
                  wakeToFullyVisible: _chatWakeOnMessage,
                  ghostOpacity: _chatIdleDim,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: m.backgroundGradient != null
                          ? BoxDecoration(gradient: m.backgroundGradient)
                          : BoxDecoration(color: m.background),
                    ),
                    if (state.fileName == null)
                      EmptyState(
                        onBrowse: _browse,
                        onLoadUrl: (url) => unawaited(_load(url)),
                        notice: _joinPrompt,
                      )
                    else if (state.status == PlaybackStatus.error)
                      VideoErrorState(
                        message: friendlyPlaybackError(
                          isUrl: isHttpUrl(state.filePath ?? ''),
                        ),
                        detail: state.errorMessage,
                        onBrowse: _browse,
                        onPasteLink: () => unawaited(_promptPasteLink()),
                        onRetry: state.filePath != null
                            ? () => unawaited(_load(state.filePath!))
                            : null,
                      )
                    else
                      VideoSurface(
                        core: _core,
                        focusNode: _videoFocus,
                        isUiIdle: _isUiIdle,
                        onUserInteraction: _onUserInteraction,
                      ),
                    if (videoVisible)
                      Positioned.fill(
                        child: FloatingReactionsOverlay(
                          emojis: _reactionFeed.stream,
                        ),
                      ),
                    // Banner + chat show even before a video is loaded, so the
                    // "waiting / friend joined" notices and chat history are
                    // visible on the load-video screen (not just while watching).
                    if (hint != null)
                      Align(
                        alignment: const Alignment(0, -0.8),
                        child: _SyncHintBanner(text: hint),
                      ),
                    AnimatedOpacity(
                      opacity: chatOpacity,
                      duration: Motion.base,
                      child: IgnorePointer(
                        ignoring: chatOpacity == 0.0,
                        child: ChatOverlay(
                          messages: _messages,
                          collapsed: _chatLayout.collapsed,
                          isUiIdle: _isUiIdle,
                          corner: _chatLayout.corner,
                          pulsing: _peekPulsing,
                          onSend: _chat.send,
                          typingLabel: _typingLabel,
                          onTypingChanged: (t) => _chat.sendTyping(isTyping: t),
                          onToggleCollapsed: _toggleChat,
                          onSnap: (result) {
                            setState(
                              () => _chatLayout = _chatLayout.applySnap(result),
                            );
                            if (_chatLayout.collapsed) _restorePlayerFocus();
                          },
                          onDraggingChanged: (d) =>
                              setState(() => _chatDragging = d),
                          onUnreadChanged: (has) =>
                              setState(() => _chatHasUnread = has),
                          widthPx: _chatLayout.widthPx,
                          heightPx: _chatLayout.heightPx,
                          onResize: (size) {
                            setState(
                              () => _chatLayout = _chatLayout.applyResize(size),
                            );
                            widget.settings.set(
                              kChatCardSizeSettingKey,
                              formatCardSize(
                                _chatLayout.widthPx!,
                                _chatLayout.heightPx!,
                              ),
                            );
                          },
                          onResetSize: () {
                            setState(
                              () => _chatLayout = _chatLayout.resetSize(),
                            );
                            widget.settings.set(kChatCardSizeSettingKey, '');
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      // Fade the gear out while the chat card is being dragged so
                      // it never covers the top-left dock hint.
                      child: AnimatedOpacity(
                        opacity: _chatDragging || _isUiIdle ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: IgnorePointer(
                          ignoring: _chatDragging || _isUiIdle,
                          child: PlayerMenuButton(
                            roomCode: widget.config.room,
                            // Wire identities for the roster + isMe match; the
                            // "you" row shows our chosen name, not a transient
                            // reconnect dedupe suffix the server may assign (#107).
                            members: <String>[_username, ..._peers],
                            myUsername: _username,
                            myDisplayName: widget.config.username,
                            currentTheme: widget.currentTheme,
                            onThemeChanged: widget.onThemeChanged,
                            onLoadVideo: _browse,
                            onPasteLink: () => unawaited(_promptPasteLink()),
                            onLeave: _leave,
                            chatAutoDim: _chatAutoDim,
                            onChatAutoDimChanged: (val) {
                              setState(() => _chatAutoDim = val);
                              widget.settings.set(
                                kChatAutoDimSettingKey,
                                val.toString(),
                              );
                            },
                            chatWakeOnMessage: _chatWakeOnMessage,
                            onChatWakeOnMessageChanged: (val) {
                              setState(() => _chatWakeOnMessage = val);
                              widget.settings.set(
                                kChatWakeOnNewMessageSettingKey,
                                val.toString(),
                              );
                            },
                            chatIdleDim: _chatIdleDim,
                            onChatIdleDimChanged: (val) {
                              setState(() => _chatIdleDim = val);
                              widget.settings.set(
                                kChatIdleDimSettingKey,
                                val.toStringAsFixed(2),
                              );
                            },
                            primarySoundId: _primarySoundId,
                            onPrimarySoundChanged: (id) {
                              setState(() => _primarySoundId = id);
                              widget.settings.set(kNotifyPrimarySoundKey, id);
                            },
                            secondarySoundId: _secondarySoundId,
                            onSecondarySoundChanged: (id) {
                              setState(() => _secondarySoundId = id);
                              widget.settings.set(kNotifySecondarySoundKey, id);
                            },
                            onPreviewSound: _previewSound,
                            logLevel: _logLevel,
                            onLogLevelChanged: _onLogLevelChanged,
                            onExportLogs: _exportLogs,
                          ),
                        ),
                      ),
                    ),
                    if (videoVisible)
                      Positioned(
                        right: 16,
                        bottom: 84,
                        child: AnimatedOpacity(
                          opacity: overlayOpacity(idle: _isUiIdle),
                          duration: Motion.base,
                          child: IgnorePointer(
                            ignoring: _isUiIdle,
                            child: ReactionBar(onReact: _chat.sendReaction),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncHintBanner extends StatelessWidget {
  const _SyncHintBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: m.background.withValues(alpha: 0.80),
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: m.border),
        ),
        child: Text(
          text,
          style: TextStyle(color: m.textPrimary, fontSize: TypeScale.label),
        ),
      ),
    );
  }
}
