import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/sync/peer_state.dart';
import '../core/sync/playback_sync_bridge.dart';
import '../core/sync/syncplay_client.dart';
import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';
import 'dev_connect_bar.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'video_surface.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _core = MediaKitVideoCore();
    _sync = SyncplayClient();
    _bridge = PlaybackSyncBridge(video: _core, sync: _sync)..start();
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
  }

  @override
  void dispose() {
    unawaited(_connSub?.cancel());
    unawaited(_presenceSub?.cancel());
    unawaited(_bridge.dispose());
    unawaited(_sync.dispose());
    unawaited(_core.dispose());
    super.dispose();
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

  void _connect({
    required String server,
    required int port,
    required String username,
    required String room,
  }) {
    unawaited(_sync.connect(
      server: server,
      port: port,
      username: username,
      room: room,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          DevConnectBar(
            connectionStatus: _syncStatus,
            onConnect: _connect,
          ),
          Expanded(
            child: VideoDropTarget(
              onFileDropped: _handleDropped,
              child: StreamBuilder<PlaybackState>(
                stream: _core.stateStream,
                initialData: _core.state,
                builder: (context, snapshot) {
                  final state = snapshot.data!;
                  if (state.fileName == null) {
                    return EmptyState(onBrowse: _browse);
                  }
                  final hint = _syncHint;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoSurface(core: _core),
                      if (hint != null)
                        Align(
                          alignment: const Alignment(0, -0.8),
                          child: _SyncHintBanner(text: hint),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncHintBanner extends StatelessWidget {
  const _SyncHintBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC1A1410),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x55D4A574)),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFFF5E6D3), fontSize: 14),
        ),
      ),
    );
  }
}
