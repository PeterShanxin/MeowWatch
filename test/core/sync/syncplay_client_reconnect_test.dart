import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
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
}
