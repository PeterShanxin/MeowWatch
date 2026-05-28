import 'dart:async';

import 'package:flutter/foundation.dart';

import 'peer_state.dart';

/// Abstract interface for room sync. Implementations may speak the Syncplay
/// protocol over a socket, or be a fake for tests. Commands in, streams out —
/// the same shape as VideoCore.
abstract class SyncCore {
  final StreamController<SyncConnectionState> _connection =
      StreamController<SyncConnectionState>.broadcast();
  final StreamController<PeerPlayState> _peer =
      StreamController<PeerPlayState>.broadcast();
  final StreamController<PresenceEvent> _presence =
      StreamController<PresenceEvent>.broadcast();
  final StreamController<ChatMessage> _chat =
      StreamController<ChatMessage>.broadcast();
  bool _disposed = false;

  Stream<SyncConnectionState> get connectionState => _connection.stream;
  Stream<PeerPlayState> get peerState => _peer.stream;
  Stream<PresenceEvent> get presence => _presence.stream;
  Stream<ChatMessage> get chat => _chat.stream;

  @protected
  void emitConnectionState(SyncConnectionState s) {
    if (!_disposed) _connection.add(s);
  }

  @protected
  void emitPeerState(PeerPlayState s) {
    if (!_disposed) _peer.add(s);
  }

  @protected
  void emitPresence(PresenceEvent e) {
    if (!_disposed) _presence.add(e);
  }

  @protected
  void emitChat(ChatMessage m) {
    if (!_disposed) _chat.add(m);
  }

  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  });

  Future<void> disconnect();

  /// Announce the locally loaded file to the room.
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  });

  /// Push the latest local playback position/paused state. Called frequently
  /// (every position tick); the implementation stores it for the next State
  /// heartbeat — it does not necessarily transmit immediately.
  void updateLocalState({required Duration position, required bool paused});

  /// Mark that the local user just changed state (play/pause/seek) so the next
  /// State carries the ignoringOnTheFly handshake. [doSeek] true for seeks.
  void notifyLocalChange({required bool doSeek});

  void sendChat(String text);

  @protected
  Future<void> disposeBackend();

  @mustCallSuper
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disposeBackend();
    await _connection.close();
    await _peer.close();
    await _presence.close();
    await _chat.close();
  }
}
