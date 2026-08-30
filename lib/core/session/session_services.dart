import '../chat/chat_store.dart';
import '../sync/playback_sync_bridge.dart';
import '../sync/syncplay_client.dart';
import '../video/video_core.dart';
import 'session_mode.dart';

/// Multiplayer hosts for one player session.
///
/// A [SessionMode.local] session holds none of these — no socket, no bridge,
/// no chat store. A [SessionMode.synced] session owns the live trio and
/// tears them down together.
class SessionServices {
  SessionServices._({required this.mode, this.sync, this.bridge, this.chat});

  factory SessionServices.local() => SessionServices._(mode: SessionMode.local);

  factory SessionServices.synced({
    required VideoCore video,
    void Function(String line)? onLog,
    bool Function({required bool verboseOnly})? shouldLog,
  }) {
    final sync = SyncplayClient(onLog: onLog, shouldLog: shouldLog);
    final bridge = PlaybackSyncBridge(video: video, sync: sync)..start();
    final chat = ChatStore(sync: sync);
    return SessionServices._(
      mode: SessionMode.synced,
      sync: sync,
      bridge: bridge,
      chat: chat,
    );
  }

  factory SessionServices.forMode({
    required SessionMode mode,
    required VideoCore video,
    void Function(String line)? onLog,
    bool Function({required bool verboseOnly})? shouldLog,
  }) {
    if (mode.isLocal) return SessionServices.local();
    return SessionServices.synced(
      video: video,
      onLog: onLog,
      shouldLog: shouldLog,
    );
  }

  final SessionMode mode;
  final SyncplayClient? sync;
  final PlaybackSyncBridge? bridge;
  final ChatStore? chat;

  bool get isLocal => mode.isLocal;
  bool get isSynced => mode.isSynced;

  Future<void> dispose() async {
    await chat?.dispose();
    await bridge?.dispose();
    await sync?.dispose();
  }
}
