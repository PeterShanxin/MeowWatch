import '../chat/chat_store.dart';
import '../sync/playback_sync_bridge.dart';
import '../sync/syncplay_client.dart';
import '../video/video_core.dart';
import 'session_mode.dart';

/// Multiplayer hosts for one player session. Starts empty (local) and can
/// [startSynced] / [stopToLocal] without recreating the media player.
class SessionServices {
  SessionServices._(this._mode);

  factory SessionServices.local() => SessionServices._(SessionMode.local);

  factory SessionServices.synced({
    required VideoCore video,
    void Function(String line)? onLog,
    bool Function({required bool verboseOnly})? shouldLog,
  }) {
    return SessionServices.local()
      ..startSynced(video: video, onLog: onLog, shouldLog: shouldLog);
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

  SessionMode _mode;
  SyncplayClient? sync;
  PlaybackSyncBridge? bridge;
  ChatStore? chat;

  SessionMode get mode => _mode;
  bool get isLocal => _mode.isLocal;
  bool get isSynced => _mode.isSynced;

  /// Spin up the Syncplay trio. No-op if already synced.
  ///
  /// [openSource] is the source the load coordinator has already accepted for
  /// [video] — pass it whenever the player is already open as the trio starts
  /// (the live Local -> Synced switch). See
  /// [PlaybackSyncBridge.adoptOpenSource].
  void startSynced({
    required VideoCore video,
    String? openSource,
    void Function(String line)? onLog,
    bool Function({required bool verboseOnly})? shouldLog,
  }) {
    if (_mode.isSynced) return;
    final client = SyncplayClient(onLog: onLog, shouldLog: shouldLog);
    sync = client;
    final playbackBridge = PlaybackSyncBridge(video: video, sync: client)
      ..start();
    bridge = playbackBridge;
    chat = ChatStore(sync: client);
    _mode = SessionMode.synced;
    // A live Local -> Synced switch hands the new bridge a player that is
    // ALREADY open, and the load coordinator will never call markSourceOpen for
    // it again. Adopt it here, or the bridge publishes nothing and the session
    // becomes drivable-but-not-driving (#252).
    if (openSource != null) playbackBridge.adoptOpenSource(openSource);
  }

  /// Tear down the Syncplay trio. No-op if already local.
  Future<void> stopToLocal() async {
    if (_mode.isLocal) return;
    final oldChat = chat;
    final oldBridge = bridge;
    final oldSync = sync;
    chat = null;
    bridge = null;
    sync = null;
    _mode = SessionMode.local;
    await oldChat?.dispose();
    await oldBridge?.dispose();
    await oldSync?.dispose();
  }

  Future<void> dispose() async {
    await stopToLocal();
  }
}
