import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/endpoint_discovery.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_core.dart';
import 'package:meowwatch/core/sync/syncplay_endpoints.dart';

/// #234 — what makes a candidate endpoint count as *working*.
///
/// The probe drives a real `SyncplayClient` against a real loopback listener,
/// so these assert on the actual client behaviour rather than on a
/// reimplementation of it. The bar is the server's Hello, which the client only
/// ever emits over a socket a completed TLS upgrade produced — every listener
/// below stops short of that and must not count.
void main() {
  const timeout = Duration(milliseconds: 500);

  group('a candidate does not count as working when', () {
    test('nothing is listening on the port', () async {
      // Bind and immediately release, so the port is almost certainly free.
      final probeSocket = await ServerSocket.bind('127.0.0.1', 0);
      final port = probeSocket.port;
      await probeSocket.close();

      final reachable = await SyncplayHandshakeProbe().call(
        SyncplayEndpoint(host: '127.0.0.1', port: port),
        timeout: timeout,
      );

      expect(reachable, isFalse);
    });

    test('the socket opens but the server never speaks', () async {
      // The whole reason a TCP connect is not proof: a dead or wrong service
      // accepts the connection just as happily as a live Syncplay server.
      final listener = await _Listener.start(reply: (_) => null);

      final reachable = await SyncplayHandshakeProbe().call(
        listener.endpoint,
        timeout: timeout,
      );

      expect(reachable, isFalse);
      expect(listener.receivedStartTlsRequest, isTrue);
      await listener.expectClientHungUp();
    });

    test('the listener speaks something other than Syncplay', () async {
      final listener = await _Listener.start(
        reply: (_) => json.encode({'not-a-syncplay-frame': true}),
      );

      final reachable = await SyncplayHandshakeProbe().call(
        listener.endpoint,
        timeout: timeout,
      );

      expect(reachable, isFalse);
      await listener.expectClientHungUp();
    });

    test('the server declines to encrypt', () async {
      // What upstream syncplay-server answers with no TLS configured. Accepting
      // it would be a plaintext downgrade, so it can never count as a working
      // endpoint for MeowWatch.
      final listener = await _Listener.start(
        reply: (_) => json.encode({
          'TLS': {'startTLS': 'false'},
        }),
      );

      final reachable = await SyncplayHandshakeProbe().call(
        listener.endpoint,
        timeout: timeout,
      );

      expect(reachable, isFalse);
      expect(
        listener.plaintextFromClient,
        isNot(contains('Hello')),
        reason: 'nothing may follow a refused upgrade',
      );
      await listener.expectClientHungUp();
    });

    test('the server skips the answer and just says Hello', () async {
      // The shape of an active downgrade: swallow the upgrade request and
      // pretend the session is already up. A Hello in the clear is not a login,
      // so it must not promote a hostile listener to "working endpoint".
      final listener = await _Listener.start(
        reply: (_) => json.encode({
          'Hello': {'username': 'probe'},
        }),
      );

      final reachable = await SyncplayHandshakeProbe().call(
        listener.endpoint,
        timeout: timeout,
      );

      expect(reachable, isFalse);
      await listener.expectClientHungUp();
    });

    test('the client reports the connection failed', () async {
      // Everything the client turns into an error state — a refused socket, a
      // rejected certificate, a failed TLS handshake — reaches the probe the
      // same way, and none of it is a working endpoint.
      final client = _ScriptedClient([
        const SyncConnectionState(status: SyncConnectionStatus.connecting),
        const SyncConnectionState(status: SyncConnectionStatus.handshaking),
        const SyncConnectionState(
          status: SyncConnectionStatus.error,
          message: 'TLS handshake failed',
        ),
      ]);

      final reachable = await SyncplayHandshakeProbe(
        createClient: ({required livenessTimeout}) => client,
      ).call(const SyncplayEndpoint(host: 'h', port: 1), timeout: timeout);

      expect(reachable, isFalse);
      expect(client.disposed, 1);
    });
  });

  group('probe lifecycle', () {
    test('reports success only once the server has said Hello', () async {
      final client = _ScriptedClient([
        const SyncConnectionState(status: SyncConnectionStatus.connecting),
        const SyncConnectionState(status: SyncConnectionStatus.handshaking),
        const SyncConnectionState(status: SyncConnectionStatus.connected),
      ]);

      final reachable = await SyncplayHandshakeProbe(
        createClient: ({required livenessTimeout}) => client,
      ).call(const SyncplayEndpoint(host: 'h', port: 1), timeout: timeout);

      expect(reachable, isTrue);
      expect(client.disposed, 1);
    });

    test('a handshake that stalls short of Hello is not success', () async {
      final client = _ScriptedClient([
        const SyncConnectionState(status: SyncConnectionStatus.connecting),
        const SyncConnectionState(status: SyncConnectionStatus.handshaking),
      ]);

      final reachable =
          await SyncplayHandshakeProbe(
            createClient: ({required livenessTimeout}) => client,
          ).call(
            const SyncplayEndpoint(host: 'h', port: 1),
            timeout: const Duration(milliseconds: 80),
          );

      expect(reachable, isFalse);
      expect(client.disposed, 1);
    });

    test('disposes the client even when the connect throws', () async {
      final client = _ScriptedClient(const [], throwOnConnect: true);

      final reachable = await SyncplayHandshakeProbe(
        createClient: ({required livenessTimeout}) => client,
      ).call(const SyncplayEndpoint(host: 'h', port: 1), timeout: timeout);

      expect(reachable, isFalse);
      expect(client.disposed, 1);
    });

    test('never dials the room or the name the user is about to use', () async {
      // A probe that reused the real identity would leave a ghost the following
      // real connect then collides with, which is how the server-assigned "_"
      // suffix appears (#93).
      final first = _ScriptedClient(const []);
      final second = _ScriptedClient(const []);
      final clients = <_ScriptedClient>[first, second];
      final probe = SyncplayHandshakeProbe(
        createClient: ({required livenessTimeout}) => clients.removeAt(0),
      );
      const short = Duration(milliseconds: 40);

      await probe.call(
        const SyncplayEndpoint(host: 'h', port: 1),
        timeout: short,
      );
      await probe.call(
        const SyncplayEndpoint(host: 'h', port: 1),
        timeout: short,
      );

      expect(first.room, startsWith('meowwatch-probe-'));
      expect(first.room, first.username);
      expect(
        first.room,
        isNot(second.room),
        reason: 'two probes must not meet in the same throwaway room',
      );
      expect(first.password, isNull);
    });

    test('passes its budget to the client as the silence watchdog', () async {
      Duration? seen;
      final client = _ScriptedClient(const []);

      await SyncplayHandshakeProbe(
        createClient: ({required livenessTimeout}) {
          seen = livenessTimeout;
          return client;
        },
      ).call(
        const SyncplayEndpoint(host: 'h', port: 1),
        timeout: const Duration(milliseconds: 30),
      );

      expect(seen, const Duration(milliseconds: 30));
    });
  });
}

/// A loopback listener that answers the client's STARTTLS request with a
/// scripted [reply] (null to stay silent).
///
/// Every scripted answer stops the client *before* it enters
/// `SecureSocket.secure`: a listener that accepts the upgrade and then fails it
/// would exercise dart:io's handshake, whose failure the client on `main` does
/// not yet catch (that is PR #265's fix, not this one's). The probe's handling
/// of that outcome is covered through the error state instead.
class _Listener {
  _Listener._(this._server);

  static Future<_Listener> start({
    required String? Function(String request) reply,
  }) async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final listener = _Listener._(server);
    server.listen((socket) {
      listener._accepted.add(socket);
      final closed = Completer<void>();
      listener._closed.add(closed.future);
      socket.listen(
        (bytes) {
          final text = utf8.decode(bytes, allowMalformed: true);
          listener.plaintextFromClient += text;
          if (!text.contains('startTLS')) return;
          listener.receivedStartTlsRequest = true;
          final answer = reply(text);
          if (answer == null) return;
          try {
            socket.add(utf8.encode('$answer\r\n'));
          } on Object {
            // The client may already be gone; nothing to assert here.
          }
        },
        // The peer closing its end is what "the probe hung up" means; the
        // sink-side `Socket.done` would only report *our* close.
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object _) {
          if (!closed.isCompleted) closed.complete();
        },
        cancelOnError: false,
      );
    });
    addTearDown(listener._close);
    return listener;
  }

  final ServerSocket _server;
  final List<Socket> _accepted = <Socket>[];
  final List<Future<void>> _closed = <Future<void>>[];

  String plaintextFromClient = '';
  bool receivedStartTlsRequest = false;

  SyncplayEndpoint get endpoint =>
      SyncplayEndpoint(host: '127.0.0.1', port: _server.port);

  /// The probe must leave nothing behind: every socket it opened is closed by
  /// the time it answers.
  Future<void> expectClientHungUp() async {
    expect(_accepted, isNotEmpty, reason: 'the probe never connected');
    await Future.wait(_closed).timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('the probe left its socket open'),
    );
  }

  Future<void> _close() async {
    for (final socket in _accepted) {
      socket.destroy();
    }
    await _server.close();
  }
}

/// A [SyncCore] that replays a fixed connection-state script, so the probe's
/// own decision logic can be exercised without a socket.
class _ScriptedClient extends SyncCore {
  _ScriptedClient(this._script, {this.throwOnConnect = false});

  final List<SyncConnectionState> _script;
  final bool throwOnConnect;

  String? room;
  String? username;
  String? password;
  int disposed = 0;

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {
    this.room = room;
    this.username = username;
    this.password = password;
    if (throwOnConnect) throw const SocketException('refused');
    for (final state in _script) {
      emitConnectionState(state);
    }
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> disposeBackend() async {}

  @override
  Future<void> dispose() async {
    disposed++;
    await super.dispose();
  }

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {}

  @override
  void notifyLocalChange({required bool doSeek}) {}

  @override
  void sendChat(String text) {}
}
