import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'peer_state.dart';
import 'ping_service.dart';
import 'sync_core.dart';
import 'sync_messages.dart';

/// Concrete SyncCore speaking the Syncplay text protocol over a TCP socket
/// upgraded to TLS. One JSON object per line, terminated `\r\n`.
class SyncplayClient extends SyncCore {
  Socket? _socket;
  final LineFramer _framer = LineFramer();
  final PingService _ping = PingService();

  String _username = '';
  String _room = '';
  String? _password;

  bool _loggedIn = false;

  // Latest local playback state for the heartbeat.
  Duration _localPosition = Duration.zero;
  bool _localPaused = true;

  // ignoringOnTheFly handshake counters.
  int _clientIgnore = 0;
  int _serverIgnore = 0;
  bool _pendingStateChange = false;
  bool _pendingDoSeek = false;

  // The most recent server latencyCalculation we must echo back.
  double? _serverLatencyCalculation;

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {
    _username = username;
    _room = room;
    _password = password;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.connecting),
    );

    try {
      final plain = await Socket.connect(server, port,
          timeout: const Duration(seconds: 10));
      // Attempt TLS upgrade first (public servers require it).
      _sendRaw(plain, encodeTlsRequest());
      emitConnectionState(
        const SyncConnectionState(status: SyncConnectionStatus.handshaking),
      );
      _attachPlainForTlsNegotiation(plain, server);
    } on SocketException catch (e) {
      emitConnectionState(SyncConnectionState(
        status: SyncConnectionStatus.error,
        message: 'Could not reach server: ${e.message}',
      ));
    }
  }

  /// Listen on the plain socket only long enough to receive the TLS answer,
  /// then upgrade to a SecureSocket and (re)attach the main listener.
  void _attachPlainForTlsNegotiation(Socket plain, String server) {
    late StreamSubscription<List<int>> sub;
    sub = plain.listen((chunk) async {
      for (final line in _framer.addChunk(chunk)) {
        if (line.isEmpty) continue;
        final decoded = decodeServerMessage(
            json.decode(line) as Map<dynamic, dynamic>);
        if (decoded is TlsMessage && decoded.startTls) {
          await sub.cancel();
          final secure = await SecureSocket.secure(
            plain,
            host: server,
            onBadCertificate: (_) => false,
          );
          _bindSocket(secure);
          _sendHello();
          return;
        } else if (decoded is ErrorMessage) {
          // Server doesn't support TLS — fall back to the plain socket.
          await sub.cancel();
          _bindSocket(plain);
          _sendHello();
          return;
        }
      }
    }, onError: (Object e) {
      emitConnectionState(SyncConnectionState(
        status: SyncConnectionStatus.error,
        message: e.toString(),
      ));
    });
  }

  void _bindSocket(Socket socket) {
    _socket = socket;
    socket.listen(
      _onChunk,
      onError: (Object e) => emitConnectionState(SyncConnectionState(
        status: SyncConnectionStatus.error,
        message: e.toString(),
      )),
      onDone: () => emitConnectionState(
        const SyncConnectionState(status: SyncConnectionStatus.disconnected),
      ),
    );
  }

  void _onChunk(List<int> chunk) {
    for (final line in _framer.addChunk(chunk)) {
      if (line.isEmpty) continue;
      late ServerMessage msg;
      try {
        msg = decodeServerMessage(json.decode(line) as Map<dynamic, dynamic>);
      } on FormatException {
        continue;
      }
      _handleMessage(msg);
    }
  }

  void _sendHello() {
    _send(encodeHello(
      username: _username,
      room: _room,
      password: _password,
    ));
  }

  void _handleMessage(ServerMessage msg) {
    switch (msg) {
      case HelloMessage():
        _loggedIn = true;
        emitConnectionState(
          const SyncConnectionState(status: SyncConnectionStatus.connected),
        );
      case PresenceMessage(:final events):
        for (final e in events) {
          emitPresence(e);
        }
      case ChatServerMessage(:final message):
        emitChat(message);
      case ErrorMessage(:final message):
        emitConnectionState(SyncConnectionState(
          status: SyncConnectionStatus.error,
          message: message,
        ));
      case StateMessage():
        _handleState(msg);
      case TlsMessage():
      case UnknownMessage():
        break;
    }
  }

  void _handleState(StateMessage msg) {
    // Track the server/client ignore handshake.
    if (msg.serverIgnore != null) {
      _serverIgnore = msg.serverIgnore!;
      _clientIgnore = 0;
    } else if (msg.clientIgnore != null && msg.clientIgnore == _clientIgnore) {
      _clientIgnore = 0;
    }

    // Remember the latency timestamp we must echo back.
    if (msg.latencyCalculation != null) {
      _serverLatencyCalculation = msg.latencyCalculation;
    }

    // Apply the peer's state unless we're mid-handshake on our own change.
    final ignoringOwnChange = _clientIgnore != 0 && _serverIgnore == 0;
    if (msg.peer != null && !ignoringOwnChange) {
      // Advance position by the one-way delay if the peer is playing.
      final adjusted = msg.peer!.paused
          ? msg.peer!
          : PeerPlayState(
              position: msg.peer!.position +
                  Duration(milliseconds: (_ping.forwardDelay * 1000).round()),
              paused: msg.peer!.paused,
              doSeek: msg.peer!.doSeek,
              setBy: msg.peer!.setBy,
            );
      emitPeerState(adjusted);
    }

    _replyState();
  }

  /// Send our own State in response to the server's (the heartbeat).
  void _replyState() {
    final stateChange = _pendingStateChange;
    if (stateChange) {
      _clientIgnore += 1;
    }

    _send(encodeState(
      position: _localPosition,
      paused: _localPaused,
      doSeek: _pendingDoSeek,
      latencyCalculation: _serverLatencyCalculation,
      clientLatencyCalculation: _ping.newTimestamp(),
      clientRtt: _ping.rtt,
      clientIgnore: _clientIgnore,
      serverIgnore: _serverIgnore,
    ));

    // Reset one-shot flags; serverIgnore is cleared once echoed.
    _pendingStateChange = false;
    _pendingDoSeek = false;
    _serverIgnore = 0;
  }

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null) return;
    socket.add(utf8.encode('${json.encode(message)}\r\n'));
  }

  void _sendRaw(Socket socket, Map<String, Object?> message) {
    socket.add(utf8.encode('${json.encode(message)}\r\n'));
  }

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {
    if (!_loggedIn) return;
    _send(encodeFile(name: name, sizeBytes: size, duration: duration));
    _send(encodeList());
  }

  @override
  void updateLocalState({required Duration position, required bool paused}) {
    _localPosition = position;
    _localPaused = paused;
  }

  @override
  void notifyLocalChange({required bool doSeek}) {
    _pendingStateChange = true;
    if (doSeek) _pendingDoSeek = true;
  }

  @override
  void sendChat(String text) {
    if (_loggedIn) _send(encodeChat(text));
  }

  @override
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    _loggedIn = false;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.disconnected),
    );
  }

  @override
  Future<void> disposeBackend() async {
    await _socket?.close();
    _socket = null;
  }
}
