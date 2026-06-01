import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'connection_watchdog.dart';
import 'peer_state.dart';
import 'ping_service.dart';
import 'sync_activity.dart';
import 'sync_core.dart';
import 'sync_follow.dart';
import 'sync_messages.dart';

/// Concrete SyncCore speaking the Syncplay text protocol over a TCP socket
/// upgraded to TLS. One JSON object per line, terminated `\r\n`.
class SyncplayClient extends SyncCore {
  SyncplayClient({
    this.onLog,
    this.livenessTimeout = const Duration(seconds: 12),
  });

  /// Optional debug sink for raw protocol traffic and follow decisions.
  final void Function(String line)? onLog;

  /// How long to tolerate silence from the server before presuming the link is
  /// dead (a half-open TCP that never fired onDone/onError). Generous relative
  /// to the ~1s State heartbeat. Injectable for tests.
  final Duration livenessTimeout;

  Socket? _socket;
  LineFramer _framer = LineFramer();
  final PingService _ping = PingService();

  late final ConnectionWatchdog _watchdog = ConnectionWatchdog(
    timeout: livenessTimeout,
    onTimeout: _onConnectionLost,
  );

  // Reconnect bookkeeping. Server/port are remembered from the first connect so
  // a dropped link can be re-established without UI involvement.
  String _server = '';
  int _port = 0;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;

  // Bumped every time we abandon or supersede a connection attempt (new dial,
  // reconnect, manual leave). The TLS negotiation runs async on a socket that
  // isn't yet bound to [_socket]; a slow handshake could otherwise complete
  // *after* its attempt was torn down and bind a zombie socket. Each
  // negotiation captures the generation it started in and bails if it no longer
  // matches.
  int _generation = 0;

  String _username = '';
  String _room = '';
  String? _password;

  bool _loggedIn = false;

  // Latest local playback state for the heartbeat.
  Duration _localPosition = Duration.zero;
  bool _localPaused = true;

  // Snapshot of the local state from just before the latest update — lets us
  // classify our OWN play/pause/seek for self-notifications (issue #27).
  Duration _prevLocalPosition = Duration.zero;
  bool _prevLocalPaused = true;

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
    _server = server;
    _port = port;
    _username = username;
    _room = room;
    _password = password;
    _manualDisconnect = false;
    _reconnectAttempt = 0;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.connecting),
    );
    await _openConnection();
  }

  /// Open (or re-open) the socket and start the TLS handshake. Shared by the
  /// initial [connect] and the auto-reconnect path; callers set the surrounding
  /// status (`connecting` vs. `reconnecting`) before invoking.
  Future<void> _openConnection() async {
    // Tear down any prior socket and stale framer state before dialing again.
    _watchdog.stop();
    _socket?.destroy();
    _socket = null;
    _framer = LineFramer();
    _loggedIn = false;
    final generation = ++_generation;

    try {
      final plain = await Socket.connect(_server, _port,
          timeout: const Duration(seconds: 10));
      // A late dial that resolves after we already moved on: drop it.
      if (generation != _generation || _manualDisconnect) {
        plain.destroy();
        return;
      }
      // Track the negotiation socket immediately so a mid-handshake teardown
      // (watchdog trip or manual leave, before _bindSocket runs) can destroy it.
      _socket = plain;
      // Attempt TLS upgrade first (public servers require it).
      _sendRaw(plain, encodeTlsRequest());
      emitConnectionState(
        const SyncConnectionState(status: SyncConnectionStatus.handshaking),
      );
      // Guard the handshake too: if the socket binds but the server never
      // completes the Hello, the watchdog trips and we retry.
      _watchdog.bump();
      _attachPlainForTlsNegotiation(plain, _server, generation);
    } on SocketException catch (e) {
      if (generation != _generation || _manualDisconnect) return;
      onLog?.call('connect failed: ${e.message}');
      _scheduleReconnect(message: 'Could not reach server: ${e.message}');
    }
  }

  /// Presume the current link dead (silent timeout, socket error, or clean
  /// close) and arm a backed-off reconnect — unless the user asked to leave.
  void _onConnectionLost() {
    if (_manualDisconnect) return;
    onLog?.call('connection lost (no server traffic within '
        '${livenessTimeout.inSeconds}s) — reconnecting');
    _scheduleReconnect();
  }

  /// Permanently stop the connection — no auto-reconnect. Used for a deliberate
  /// leave and for a fatal server protocol error (rejected room/password). Bumps
  /// the generation so a trailing onDone from the closing socket is ignored.
  void _stopReconnecting() {
    _manualDisconnect = true;
    _generation++;
    _watchdog.stop();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect({String? message}) {
    if (_manualDisconnect) return;
    _watchdog.stop();
    // Invalidate any in-flight handshake from the attempt we're abandoning.
    _generation++;
    // Clear _socket BEFORE destroying so the destroyed socket's trailing
    // onDone/onError can't observe itself as the live socket.
    final old = _socket;
    _socket = null;
    old?.destroy();
    _loggedIn = false;
    // Surface the gap to the UI so playback auto-pauses while we recover.
    emitConnectionState(SyncConnectionState(
      status: SyncConnectionStatus.reconnecting,
      message: message,
    ));
    _reconnectTimer?.cancel();
    final delay = reconnectBackoff(attempt: _reconnectAttempt);
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      if (_manualDisconnect) return;
      unawaited(_openConnection());
    });
  }

  /// Listen on the plain socket only long enough to receive the TLS answer,
  /// then upgrade to a SecureSocket and (re)attach the main listener.
  ///
  /// The existing subscription is *paused* (not cancelled) and handed to
  /// [SecureSocket.secure] via `subscription:`, so any bytes already buffered
  /// for that subscription are carried into the TLS handshake. Cancelling
  /// instead would drop them and break the handshake.
  void _attachPlainForTlsNegotiation(Socket plain, String server, int generation) {
    // True once this attempt is superseded (reconnect/manual leave) or done —
    // every completion path must bail rather than bind a zombie socket.
    bool stale() => generation != _generation || _manualDisconnect;
    var upgraded = false;
    late StreamSubscription<Uint8List> sub;
    sub = plain.listen((chunk) async {
      if (upgraded) return;
      for (final line in _framer.addChunk(chunk)) {
        if (line.isEmpty) continue;
        final decoded =
            decodeServerMessage(json.decode(line) as Map<dynamic, dynamic>);
        if (decoded is TlsMessage && decoded.startTls) {
          upgraded = true;
          if (stale()) return;
          // Pause (don't cancel) so SecureSocket.secure can detach this
          // subscription and carry any buffered bytes into the handshake.
          sub.pause();
          final secure = await SecureSocket.secure(
            plain,
            host: server,
            onBadCertificate: (_) => false,
          );
          // The await above can outlive a teardown — drop the upgraded socket
          // rather than binding it over a newer attempt.
          if (stale()) {
            secure.destroy();
            return;
          }
          _bindSocket(secure, generation);
          _sendHello();
          return;
        } else if (decoded is ErrorMessage) {
          // Server doesn't support TLS — fall back to the plain socket.
          upgraded = true;
          if (stale()) return;
          await sub.cancel();
          if (stale()) return;
          _bindSocket(plain, generation);
          _sendHello();
          return;
        }
      }
    }, onError: (Object e) {
      if (stale()) return;
      onLog?.call('tls negotiation error: $e');
      _onConnectionLost();
    });
  }

  void _bindSocket(Socket socket, int generation) {
    _socket = socket;
    // onDone/onError can fire *after* we've already torn this socket down (a
    // destroy() during reconnect still flushes a final close event). Guard on
    // the generation so only the currently-live socket can trigger a reconnect
    // — otherwise a stale callback would schedule a second one, double-counting
    // the backoff and resetting the timer.
    socket.listen(
      _onChunk,
      onError: (Object e) {
        if (generation != _generation) return;
        onLog?.call('socket error: $e');
        _onConnectionLost();
      },
      onDone: () {
        if (generation != _generation) return;
        _onConnectionLost();
      },
    );
  }

  void _onChunk(List<int> chunk) {
    // Any byte from the server proves the link is alive — reset the watchdog.
    _watchdog.bump();
    for (final line in _framer.addChunk(chunk)) {
      if (line.isEmpty) continue;
      onLog?.call('<< $line');
      late ServerMessage msg;
      try {
        msg = decodeServerMessage(
          json.decode(line) as Map<dynamic, dynamic>,
          selfRoom: _room,
        );
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
        // A completed login means the (re)connect succeeded — reset the backoff
        // so the next drop starts over from the short end.
        _reconnectAttempt = 0;
        emitConnectionState(
          const SyncConnectionState(status: SyncConnectionStatus.connected),
        );
        // Ask for the room roster immediately — otherwise a client that joins
        // without a file loaded never learns who is already here (it would only
        // request the list when announcing a file), and sits on "waiting for a
        // friend" while everyone else can see it.
        _send(encodeList());
      case PresenceMessage(:final events, :final files):
        for (final e in events) {
          emitPresence(e);
        }
        for (final f in files) {
          if (f.username != _username) emitPeerFile(f);
        }
      case PeerFileMessage(:final files):
        for (final f in files) {
          if (f.username != _username) emitPeerFile(f);
        }
      case RosterMessage(:final usernames, :final files):
        for (final name in usernames) {
          if (name != _username) {
            emitPresence(PresenceEvent(
                username: name,
                kind: PresenceKind.joined,
                fromRoster: true));
          }
        }
        for (final f in files) {
          if (f.username != _username) emitPeerFile(f);
        }
      case ChatServerMessage(:final message):
        emitChat(message);
      case ErrorMessage(:final message):
        // A server protocol error is a deliberate rejection (bad room/password,
        // room full, kicked) — the server closes the socket right after. Stop
        // reconnecting so that trailing close doesn't restart an endless loop
        // with the same bad credentials; leave the user on the actionable error.
        _stopReconnecting();
        final old = _socket;
        _socket = null;
        old?.destroy();
        _loggedIn = false;
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

    // Measure our RTT: the server echoes the clientLatencyCalculation we sent
    // last, so the round trip is now - that timestamp. Without this, _ping.rtt
    // stays 0 and forwardDelay never compensates for network latency.
    final rtt = rttSampleFromEcho(
      echoedTimestamp: msg.clientLatencyCalculation,
      nowEpochSeconds: _ping.newTimestamp(),
    );
    if (rtt != null) _ping.recordRtt(rtt);

    // Decide whether the local player should follow the room's global state.
    // Skipped while mid-handshake on our own change, OR while we have a local
    // change queued but not yet sent (it would otherwise be clobbered by the
    // stale global state the server is still echoing).
    final ignoringOwnChange =
        _pendingStateChange || (_clientIgnore != 0 && _serverIgnore == 0);
    if (msg.peer != null && !ignoringOwnChange) {
      // Advance position by the one-way delay if the room is playing.
      final global = msg.peer!.paused
          ? msg.peer!
          : PeerPlayState(
              position: msg.peer!.position +
                  Duration(milliseconds: (_ping.forwardDelay * 1000).round()),
              paused: msg.peer!.paused,
              doSeek: msg.peer!.doSeek,
              setBy: msg.peer!.setBy,
            );
      final action = decideFollow(
        global: global,
        localPaused: _localPaused,
        localPosition: _localPosition,
        username: _username,
      );
      onLog?.call(
          'FOLLOW global(pos=${global.positionSeconds}s paused=${global.paused} '
          'doSeek=${global.doSeek} setBy=${global.setBy}) '
          'local(pos=${_localPosition.inMilliseconds / 1000}s paused=$_localPaused) '
          '=> apply=${action.shouldApply}');
      if (action.shouldApply) {
        // Surface this as a notification BEFORE we overwrite our local snapshot
        // below — the classifier compares the peer's target to where we were.
        final activity = classifySyncActivity(
          global: global,
          localPaused: _localPaused,
          localPosition: _localPosition,
        );
        if (activity != null) emitActivity(activity);

        // Adopt the applied state into our local cache immediately. The video
        // applies it asynchronously, so without this the very next heartbeat
        // would report the STALE pre-apply state (e.g. pos=0 paused=true) and
        // the server would treat that as a brand-new change — the root of the
        // ping-pong fight.
        _localPosition = action.position;
        _localPaused = action.paused;
        emitPeerState(PeerPlayState(
          position: action.position,
          paused: action.paused,
          doSeek: global.doSeek,
          setBy: global.setBy,
        ));
      }
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
    final line = json.encode(message);
    onLog?.call('>> $line');
    socket.add(utf8.encode('$line\r\n'));
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
    _prevLocalPosition = _localPosition;
    _prevLocalPaused = _localPaused;
    _localPosition = position;
    _localPaused = paused;
  }

  @override
  void notifyLocalChange({required bool doSeek}) {
    _pendingStateChange = true;
    if (doSeek) _pendingDoSeek = true;

    // Announce our own action locally (issue #27). The peer-side path in
    // _handleState only fires for *peers*; without this our own play/pause/seek
    // would be silent on our own screen. Suppressed until we have a username to
    // attribute it to.
    if (!_loggedIn || _username.isEmpty) return;
    final activity = classifyLocalActivity(
      doSeek: doSeek,
      paused: _localPaused,
      wasPaused: _prevLocalPaused,
      position: _localPosition,
      previousPosition: _prevLocalPosition,
      username: _username,
    );
    if (activity != null) emitActivity(activity);
  }

  /// Test hook: simulate a completed login so local-change classification has a
  /// username to attribute, without standing up a real socket/handshake.
  @visibleForTesting
  void debugMarkLoggedIn(String username) {
    _username = username;
    _loggedIn = true;
  }

  /// Test hook: pretend the server fell silent / the socket dropped, exercising
  /// the reconnect state machine without a real network. Mirrors what the
  /// watchdog, socket onDone, and socket onError all funnel into.
  @visibleForTesting
  void debugSimulateConnectionLost() => _onConnectionLost();

  /// Test hook: how many reconnect attempts have been scheduled since the last
  /// successful login (resets to 0 on Hello). Lets a test assert the backoff
  /// advances on repeated drops.
  @visibleForTesting
  int get debugReconnectAttempt => _reconnectAttempt;

  /// Test hook: is a reconnect currently armed?
  @visibleForTesting
  bool get debugReconnectScheduled => _reconnectTimer?.isActive ?? false;

  /// Test hook: route a decoded server message through the normal handler,
  /// without a socket — e.g. to exercise the fatal-error stop path.
  @visibleForTesting
  void debugHandleMessage(ServerMessage msg) => _handleMessage(msg);

  @override
  void sendChat(String text) {
    if (_loggedIn) _send(encodeChat(text));
  }

  @override
  Future<void> disconnect() async {
    // User asked to leave: stop the watchdog and cancel any pending reconnect so
    // we don't immediately dial back in.
    _stopReconnecting();
    // destroy(), not close(): a half-open socket's close() awaits a flush that
    // can never complete (the peer is gone), which is exactly what wedged the
    // "Leave room" button. destroy() drops it immediately. Clear _socket first
    // so the trailing close event can't see itself as live.
    final old = _socket;
    _socket = null;
    old?.destroy();
    _loggedIn = false;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.disconnected),
    );
  }

  @override
  Future<void> disposeBackend() async {
    _stopReconnecting();
    final old = _socket;
    _socket = null;
    old?.destroy();
  }
}
