// Throwaway smoke test: connect to a public Syncplay server, complete the
// TLS + Hello handshake, announce a fake file, and observe heartbeats. Run:
//   <flutter>/bin/flutter test tool/sync_smoke.dart
//
// Not part of the normal unit suite (it hits the network); run explicitly.
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/syncplay_client.dart';

void main() {
  test('connects to syncplay.pl and reaches connected', () async {
    final client = SyncplayClient();
    final reachedConnected = <SyncConnectionStatus>[];

    client.connectionState.listen((s) {
      reachedConnected.add(s.status);
      // ignore: avoid_print
      print('CONNECTION: ${s.status}${s.message != null ? ' — ${s.message}' : ''}');
    });
    client.presence.listen((e) {
      // ignore: avoid_print
      print('PRESENCE: ${e.username} ${e.kind}');
    });
    client.peerState.listen((p) {
      // ignore: avoid_print
      print('PEER: pos=${p.position} paused=${p.paused} doSeek=${p.doSeek}');
    });

    await client.connect(
      server: 'syncplay.pl',
      port: 8999,
      username: 'meow-smoke',
      room: 'meow-smoke-room',
    );

    await Future<void>.delayed(const Duration(seconds: 4));
    client.announceFile(
      name: 'smoke.mkv',
      size: 123456,
      duration: const Duration(minutes: 42),
    );
    client.updateLocalState(position: const Duration(seconds: 1), paused: true);

    await Future<void>.delayed(const Duration(seconds: 4));
    await client.disconnect();
    await client.dispose();

    expect(reachedConnected, contains(SyncConnectionStatus.connected));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
