import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_messages.dart';
import 'package:meowwatch/core/sync/syncplay_client.dart';

/// State-machine coverage for the half-open-connection fix. A real handshake
/// needs a TLS server with a cert the client trusts (it rejects bad certs), so
/// the socket plumbing is exercised manually in the app; here we drive the
/// reconnect logic through test hooks that mirror exactly what the watchdog,
/// socket onDone, and socket onError funnel into.
void main() {
  late SyncplayClient client;
  late List<SyncConnectionStatus> statuses;

  setUp(() {
    client = SyncplayClient();
    statuses = <SyncConnectionStatus>[];
    client.connectionState.listen((s) => statuses.add(s.status));
  });

  tearDown(() => client.dispose());

  test('a lost link moves to reconnecting and arms a retry', () async {
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);

    expect(statuses, contains(SyncConnectionStatus.reconnecting));
    expect(client.debugReconnectScheduled, isTrue);
    expect(client.debugReconnectAttempt, 1);
  });

  test('repeated drops advance the backoff attempt counter', () async {
    client.debugSimulateConnectionLost();
    client.debugSimulateConnectionLost();
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);

    expect(client.debugReconnectAttempt, 3);
    expect(client.debugReconnectScheduled, isTrue);
  });

  test('manual disconnect cancels reconnect and stays disconnected', () async {
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);
    expect(client.debugReconnectScheduled, isTrue);

    await client.disconnect();
    expect(client.debugReconnectScheduled, isFalse,
        reason: 'leaving must cancel the armed retry');
    expect(statuses.last, SyncConnectionStatus.disconnected);

    // A drop arriving after a manual leave must NOT restart reconnection.
    final before = List<SyncConnectionStatus>.from(statuses);
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);
    expect(statuses, before, reason: 'no new status after manual leave');
    expect(client.debugReconnectScheduled, isFalse);
  });

  test('disconnect with no live socket completes quickly (never hangs)',
      () async {
    // The wedged "Leave room" came from awaiting close() on a half-open socket.
    // disconnect() must always resolve promptly regardless of socket state.
    await client.disconnect().timeout(const Duration(seconds: 1));
    expect(statuses.last, SyncConnectionStatus.disconnected);
  });

  test('a fatal server error stops reconnecting (no endless loop)', () async {
    // A rejected room/password: the server sends Error then closes the socket.
    // The trailing close must NOT restart the loop with the same bad creds —
    // the user stays on the actionable error. (Codex review #49.)
    client.debugHandleMessage(const ErrorMessage('Invalid password'));
    await Future<void>.delayed(Duration.zero);

    expect(statuses.last, SyncConnectionStatus.error);
    expect(client.debugReconnectScheduled, isFalse);

    // The socket's onDone arrives after Error — simulate it; still no reconnect.
    client.debugSimulateConnectionLost();
    await Future<void>.delayed(Duration.zero);
    expect(statuses, isNot(contains(SyncConnectionStatus.reconnecting)));
    expect(statuses.last, SyncConnectionStatus.error);
  });

  test('manual leave mid-handshake tears down and never reconnects', () async {
    // A server that accepts the TCP connection but never answers the TLS
    // request leaves the client stuck in negotiation with the (unbound)
    // handshake socket live. Leaving now must destroy it and stay disconnected
    // — the generation guard must stop the dangling negotiation from later
    // binding a zombie socket. (Codex review #49.)
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final accepted = <Socket>[];
    server.listen((s) {
      accepted.add(s);
      s.listen((_) {}); // read & ignore; never reply
    });
    addTearDown(() async {
      for (final s in accepted) {
        s.destroy();
      }
      await server.close();
    });

    await client.connect(
      server: '127.0.0.1',
      port: server.port,
      username: 'me',
      room: 'r',
    );
    // We're now mid-handshake (handshaking emitted, no Hello will ever arrive).
    await _until(() => statuses.contains(SyncConnectionStatus.handshaking));
    expect(statuses, contains(SyncConnectionStatus.handshaking));

    await client.disconnect().timeout(const Duration(seconds: 1));
    expect(statuses.last, SyncConnectionStatus.disconnected);
    expect(client.debugReconnectScheduled, isFalse);

    // Let any late negotiation callback fire — it must be ignored.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(statuses, isNot(contains(SyncConnectionStatus.reconnecting)));
    expect(statuses.last, SyncConnectionStatus.disconnected);
  });
}

/// Poll [predicate] until true or a hard deadline, so tests don't hang forever.
Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
