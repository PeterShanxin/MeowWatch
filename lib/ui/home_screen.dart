import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/chat/chat_store.dart';
import '../core/connect/room_config.dart';
import '../core/data/stores.dart';
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
import 'video_surface.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.config,
    required this.history,
    required this.currentTheme,
    required this.onThemeChanged,
    super.key,
  });

  final RoomConfig config;
  final HistoryStore history;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MediaKitVideoCore _core;
  late final SyncplayClient _sync;
  late final PlaybackSyncBridge _bridge;

  SyncConnectionStatus _syncStatus = SyncConnectionStatus.disconnected;
  final Set<String> _peers = <String>{};
  StreamSubscription<SyncConnectionState>? _connSub;
  StreamSubscription<PresenceEvent>? _presenceSub;
  StreamSubscription<PlaybackState>? _noticeSub;
  StreamSubscription<PeerFile>? _peerFileSub;

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
  ChatOverlayLayout _chatLayout = const ChatOverlayLayout();
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

  @override
  void initState() {
    super.initState();
    _core = MediaKitVideoCore();
    _sync = SyncplayClient();
    _bridge = PlaybackSyncBridge(video: _core, sync: _sync)..start();
    _chat = ChatStore(sync: _sync);
    _chatSub = _chat.stream.listen((msgs) {
      if (!mounted) return;
      setState(() => _messages = msgs);
      if (_chatLayout.collapsed) _pulsePeek();
    });
    _reactionSub = _chat.reactions.listen((e) {
      if (mounted && !_reactionFeed.isClosed) _reactionFeed.add(e.emoji);
    });
    _typingSub = _chat.typing.listen(_onTyping);
    _connSub = _sync.connectionState.listen((s) {
      if (mounted) {
        setState(() {
          _syncStatus = s.status;
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
            _showPresenceNotice('🐾 ${e.username} joined');
            _chat.addSystem('${e.username} joined the room');
          }
        } else {
          _peers.remove(e.username);
          if (_peerFile?.username == e.username) _peerFile = null;
          _showPresenceNotice('👋 ${e.username} left');
          _chat.addSystem('${e.username} left the room');
        }
        _evaluateSyncHealth();
      });
    });
    _peerFileSub = _sync.peerFile.listen((f) {
      if (mounted) setState(() => _peerFile = f);
    });
    // Clear the auto-pause banner once the user manually resumes playback.
    _noticeSub = _core.stateStream.listen((s) {
      if (!mounted) return;
      if (_autoPausedNotice && s.status == PlaybackStatus.playing) {
        setState(() => _autoPausedNotice = false);
      }
    });

    _username = widget.config.username;
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_saveResumePosition());
    });
    unawaited(_sync.connect(
      server: widget.config.server,
      port: widget.config.port,
      username: widget.config.username,
      room: widget.config.room,
      password: widget.config.password,
    ));
    final resume = widget.config.resumeFilePath;
    if (resume != null) {
      unawaited(_resume(resume, widget.config.resumePositionMs));
    }
  }

  @override
  void dispose() {
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
    _presenceTimer?.cancel();
    _autoPauseTimer?.cancel();
    unawaited(_bridge.dispose());
    unawaited(_sync.dispose());
    unawaited(_core.dispose());
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

  void _pulsePeek() {
    setState(() => _peekPulsing = true);
    _peekTimer?.cancel();
    _peekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _peekPulsing = false);
    });
  }

  /// Show a transient banner (e.g. "X joined"); auto-clears after a few
  /// seconds. Call inside setState.
  void _showPresenceNotice(String text) {
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
            wasHealthy: _syncHealthy, nowHealthy: nowHealthy, isPlaying: isPlaying) &&
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
  String? get _syncHint {
    if (_syncStatus != SyncConnectionStatus.connected) {
      return 'Connect to a room to watch together';
    }
    if (_peers.isEmpty) {
      return 'Waiting for a friend to join…';
    }
    return null;
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
    );
  }

  Future<void> _saveResumePosition() async {
    final state = _core.state;
    final path = state.filePath;
    if (path == null) return;
    await widget.history.updatePosition(
      filePath: path,
      positionMs: state.position.inMilliseconds,
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
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            setState(() => _chatLayout = _chatLayout.toggle());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
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
                    VideoSurface(core: _core),
                  if (state.fileName != null)
                    Positioned.fill(
                      child: FloatingReactionsOverlay(
                          emojis: _reactionFeed.stream),
                    ),
                  if (state.fileName != null && hint != null)
                    Align(
                      alignment: const Alignment(0, -0.8),
                      child: _SyncHintBanner(text: hint),
                    ),
                  if (state.fileName != null)
                    ChatOverlay(
                      messages: _messages,
                      myUsername: _username,
                      collapsed: _chatLayout.collapsed,
                      corner: _chatLayout.corner,
                      pulsing: _peekPulsing,
                      onSend: _chat.send,
                      typingLabel: _typingLabel,
                      onTypingChanged: (t) => _chat.sendTyping(isTyping: t),
                      onToggleCollapsed: () =>
                          setState(() => _chatLayout = _chatLayout.toggle()),
                      onSnap: (result) => setState(
                          () => _chatLayout = _chatLayout.applySnap(result)),
                    ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: PlayerMenuButton(
                      roomCode: widget.config.room,
                      members: <String>[_username, ..._peers],
                      myUsername: _username,
                      currentTheme: widget.currentTheme,
                      onThemeChanged: widget.onThemeChanged,
                      onLoadVideo: _browse,
                      onLeave: _leave,
                    ),
                  ),
                  if (state.fileName != null)
                    Positioned(
                      right: 16,
                      bottom: 84,
                      child: ReactionBar(onReact: _chat.sendReaction),
                    ),
                ],
              );
            },
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
        child: Text(
          text,
          style: TextStyle(color: m.textPrimary, fontSize: 14),
        ),
      ),
    );
  }
}

