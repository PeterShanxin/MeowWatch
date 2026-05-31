import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../core/chat/chat_store.dart';
import '../core/connect/room_config.dart';
import '../core/data/settings_store.dart';
import '../core/data/stores.dart';
import '../core/debug/debug_log.dart';
import '../core/sync/auto_pause.dart';
import '../core/sync/file_match.dart';
import '../core/sync/peer_state.dart';
import '../core/sync/playback_sync_bridge.dart';
import '../core/sync/syncplay_client.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';
import '../core/video/seek_when_ready.dart';
import 'chat/chat_overlay.dart';
import 'chat/chat_overlay_layout.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'player_menu_button.dart';
import 'reactions/floating_reactions.dart';
import 'reactions/reaction_bar.dart';
import 'sync_activity_text.dart';
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
  final DebugLog _syncLog = DebugLog.temp('meowwatch_sync.log');
  late final Player _audioPlayer;

  // Notification chime: a bundled asset (portable, no dependency on a
  // system-specific sound file), throttled so a burst of messages while
  // unfocused doesn't stack overlapping playbacks.
  static const String _notifySoundAsset = 'asset:///assets/sounds/notify.wav';
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

  /// Most recent file a peer announced, and our own loaded file's byte size —
  /// together they drive the file-mismatch warning. MeowWatch is a two-person
  /// app, so tracking a single peer file is sufficient; a later announcement
  /// (or the peer leaving) replaces/clears it.
  PeerFile? _peerFile;
  int? _localFileSizeBytes;

  /// Was the session in sync (connected + a peer present) at the last check?
  /// Used to detect the healthy -> unhealthy edge that triggers auto-pause.
  bool _syncHealthy = false;

  /// True while we've auto-paused because sync dropped; drives the banner.
  bool _autoPausedNotice = false;

  /// Transient banner when a friend joins/rejoins the room (auto-clears).
  String? _presenceNotice;
  Timer? _presenceTimer;

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
  bool _chatAutoDim = true;

  @override
  void initState() {
    super.initState();
    _initSettings();
    _onUserInteraction();
    _chatLayout = ChatOverlayLayout(
      widthPx: widget.initialWidthPx,
      heightPx: widget.initialHeightPx,
    );
    _syncLog.start();
    _core = MediaKitVideoCore();
    _sync = SyncplayClient(onLog: _syncLog.call);
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
        final focused = await windowManager.isFocused();
        if (!mounted || focused) return;
        if (_notifyClock.isRunning && _notifyClock.elapsed < _notifyThrottle) {
          return;
        }
        _notifyClock
          ..reset()
          ..start();
        try {
          await _audioPlayer.open(Media(_notifySoundAsset), play: true);
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
          if (s.status != SyncConnectionStatus.connected) _peers.clear();
          _evaluateSyncHealth();
        });
      }
      if (s.status == SyncConnectionStatus.connected) {
        unawaited(_announceCurrentFile());
      }
    });
    _presenceSub = _sync.presence.listen((e) {
      if (!mounted) return;
      setState(() {
        if (e.kind == PresenceKind.joined) {
          final isNew = _peers.add(e.username);
          // Roster entries (people already here when we arrived) update
          // membership silently; only a live join gets a banner + event line.
          if (isNew && !e.fromRoster) {
            _showTransientNotice('🐾 ${e.username} joined');
            _chat.addSystem('${e.username} joined the room');
          }
        } else {
          _peers.remove(e.username);
          if (_peerFile?.username == e.username) _peerFile = null;
          _showTransientNotice('👋 ${e.username} left');
          _chat.addSystem('${e.username} left the room');
        }
        _evaluateSyncHealth();
      });
    });
    _peerFileSub = _sync.peerFile.listen((f) {
      if (mounted) setState(() => _peerFile = f);
    });
    _activitySub = _sync.activity.listen((a) {
      if (!mounted) return;
      final t = syncActivityText(a);
      setState(() => _showTransientNotice(t.banner));
      _chat.addSystem(t.chatLine);
    });
    _noticeSub = _core.stateStream.listen((s) {
      if (!mounted) return;
      if (_autoPausedNotice && s.status == PlaybackStatus.playing) {
        setState(() => _autoPausedNotice = false);
      }
      if (_isUiIdle && s.status != PlaybackStatus.playing) {
        setState(() => _isUiIdle = false);
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
    final resume = widget.config.resumeFilePath;
    if (resume != null) {
      unawaited(_resume(resume, widget.config.resumePositionMs));
    }
  }

  Future<void> _initSettings() async {
    final dimSetting = await widget.settings.get(kChatAutoDimSettingKey);
    if (dimSetting == 'false' && mounted) {
      setState(() => _chatAutoDim = false);
    }
  }

  void _onUserInteraction() {
    if (_isUiIdle) setState(() => _isUiIdle = false);
    _uiIdleTimer?.cancel();
    _uiIdleTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_core.state.status == PlaybackStatus.playing) {
        setState(() => _isUiIdle = true);
      }
    });
  }

  @override
  void dispose() {
    _uiIdleTimer?.cancel();
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
    _presenceTimer?.cancel();
    _autoPauseTimer?.cancel();
    unawaited(_bridge.dispose());
    unawaited(_sync.dispose());
    unawaited(_core.dispose());
    unawaited(_audioPlayer.dispose());
    unawaited(_syncLog.close());
    _videoFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  /// Track a peer's typing state (ignoring our own echoed signal). A 5s
  /// watchdog clears them in case the "stopped" signal is dropped.
  void _onTyping(TypingEvent e) {
    if (!mounted || e.username == _username) return;
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
      _autoPauseTimer?.cancel();
      _autoPauseTimer = null;
      _autoPausedNotice = false;
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
      unawaited(_core.pause());
      setState(() => _autoPausedNotice = true);
    }
  }

  /// Banner text shown over the video, or null when nothing to say. Priority:
  /// a fresh "friend joined" notice, then a file-mismatch warning, then the
  /// auto-pause reason, then the plain waiting/connect hint.
  String? get _banner {
    if (_presenceNotice != null) return _presenceNotice;
    final mismatch = _fileMismatchBanner;
    if (mismatch != null) return mismatch;
    if (_autoPausedNotice) return '⏸ Paused — lost sync with your friend';
    return _syncHint;
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
    return '⚠ Different file — ${peer.username} has "${peer.name}"';
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
    await _core.load(path);
    await _announceCurrentFile();
    await _recordOpen(path);
  }

  Future<void> _resume(String path, int positionMs) async {
    await _load(path);
    await seekWhenReady(_core, Duration(milliseconds: positionMs));
  }

  Future<void> _recordOpen(String path) async {
    final state = _core.state;
    var size = 0;
    try {
      size = await File(path).length();
    } on FileSystemException {
      size = 0;
    }
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

  Future<void> _announceCurrentFile() async {
    final state = _core.state;
    final path = state.filePath;
    if (path == null) return;
    var size = 0;
    try {
      size = await File(path).length();
    } on FileSystemException {
      size = 0;
    }
    _sync.announceFile(
      name: state.fileName ?? path,
      size: size,
      duration: state.duration,
    );
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
              final hint = _banner;
              return Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: m.backgroundGradient != null
                        ? BoxDecoration(gradient: m.backgroundGradient)
                        : BoxDecoration(color: m.background),
                  ),
                  if (state.fileName == null)
                    EmptyState(onBrowse: _browse)
                  else
                    VideoSurface(
                      core: _core,
                      focusNode: _videoFocus,
                      isUiIdle: _isUiIdle,
                      onUserInteraction: _onUserInteraction,
                    ),
                  if (state.fileName != null)
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
                  if (hint != null)
                    Align(
                      alignment: const Alignment(0, -0.8),
                      child: _SyncHintBanner(text: hint),
                    ),
                  AnimatedOpacity(
                    opacity: _isUiIdle
                        ? (_chatLayout.collapsed ? 0.0 : (_chatAutoDim ? 0.1 : 1.0))
                        : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: _isUiIdle && _chatLayout.collapsed,
                      child: ChatOverlay(
                        messages: _messages,
                        myUsername: _username,
                        collapsed: _chatLayout.collapsed,
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
                        onDraggingChanged: (d) => setState(() => _chatDragging = d),
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
                          setState(() => _chatLayout = _chatLayout.resetSize());
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
                          members: <String>[_username, ..._peers],
                          myUsername: _username,
                          currentTheme: widget.currentTheme,
                          onThemeChanged: widget.onThemeChanged,
                          onLoadVideo: _browse,
                          onLeave: _leave,
                          chatAutoDim: _chatAutoDim,
                          onChatAutoDimChanged: (val) {
                            setState(() => _chatAutoDim = val);
                            widget.settings.set(kChatAutoDimSettingKey, val.toString());
                          },
                        ),
                      ),
                    ),
                  ),
                  if (state.fileName != null)
                    Positioned(
                      right: 16,
                      bottom: 84,
                      child: AnimatedOpacity(
                        opacity: _isUiIdle ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 200),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: m.background.withValues(alpha: 0.80),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: m.border),
        ),
        child: Text(text, style: TextStyle(color: m.textPrimary, fontSize: 14)),
      ),
    );
  }
}
