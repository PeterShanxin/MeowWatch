import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/chat/chat_store.dart';
import '../core/connect/room_config.dart';
import '../core/data/stores.dart';
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

  late final ChatStore _chat;
  ChatOverlayLayout _chatLayout = const ChatOverlayLayout();
  List<ChatMessage> _messages = const <ChatMessage>[];
  late String _username;
  bool _peekPulsing = false;
  Timer? _peekTimer;
  Timer? _historyTimer;
  StreamSubscription<List<ChatMessage>>? _chatSub;

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
    _connSub = _sync.connectionState.listen((s) {
      if (mounted) {
        setState(() {
          _syncStatus = s.status;
          if (s.status != SyncConnectionStatus.connected) _peers.clear();
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
          _peers.add(e.username);
        } else {
          _peers.remove(e.username);
        }
      });
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
    unawaited(_chat.dispose());
    unawaited(_connSub?.cancel());
    unawaited(_presenceSub?.cancel());
    unawaited(_bridge.dispose());
    unawaited(_sync.dispose());
    unawaited(_core.dispose());
    super.dispose();
  }

  void _pulsePeek() {
    setState(() => _peekPulsing = true);
    _peekTimer?.cancel();
    _peekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _peekPulsing = false);
    });
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
              final hint = _syncHint;
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
                      currentTheme: widget.currentTheme,
                      onThemeChanged: widget.onThemeChanged,
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
                      onToggleCollapsed: () =>
                          setState(() => _chatLayout = _chatLayout.toggle()),
                      onSnap: (result) => setState(
                          () => _chatLayout = _chatLayout.applySnap(result)),
                    ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _LeaveButton(onLeave: _leave),
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

class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onLeave});

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Material(
      color: m.background.withValues(alpha: 0.80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: m.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onLeave,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back, size: 16, color: m.textPrimary),
              const SizedBox(width: 6),
              Text('Leave',
                  style: TextStyle(color: m.textPrimary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
