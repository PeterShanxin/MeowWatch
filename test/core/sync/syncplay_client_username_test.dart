import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_messages.dart';
import 'package:meowwatch/core/sync/syncplay_client.dart';

/// Regression for #40: the Syncplay server deduplicates colliding usernames by
/// appending a suffix ("meow" -> "meow_") and echoes the assigned name back in
/// its Hello reply. The client must adopt that name, otherwise our own identity
/// diverges from what peers (and the server's chat echo) call us — flipping
/// chat-bubble ownership and mislabelling the gear member list.
void main() {
  test('adopts the server-assigned username from the Hello reply', () async {
    final client = SyncplayClient();
    final states = <SyncConnectionState>[];
    final sub = client.connectionState.listen(states.add);

    client.debugHandleMessage(const HelloMessage(username: 'meow_'));
    await Future<void>.delayed(Duration.zero);

    expect(states.last.status, SyncConnectionStatus.connected);
    expect(states.last.username, 'meow_');

    await sub.cancel();
    await client.dispose();
  });

  test('treats the assigned name as self, not as a peer', () async {
    final client = SyncplayClient();
    final peers = <String>[];
    final sub = client.presence.listen((e) => peers.add(e.username));

    client.debugHandleMessage(const HelloMessage(username: 'meow_'));
    // Roster echoes us back under the assigned name alongside a real peer.
    client.debugHandleMessage(const RosterMessage(['meow_', 'lin']));
    await Future<void>.delayed(Duration.zero);

    // Only the genuine peer surfaces; 'meow_' is now us.
    expect(peers, ['lin']);

    await sub.cancel();
    await client.dispose();
  });

  test('a blank assigned username leaves the requested name intact', () async {
    final client = SyncplayClient();
    final states = <SyncConnectionState>[];
    final sub = client.connectionState.listen(states.add);

    client.debugMarkLoggedIn('lin');
    client.debugHandleMessage(const HelloMessage());
    await Future<void>.delayed(Duration.zero);

    expect(states.last.username, 'lin');

    await sub.cancel();
    await client.dispose();
  });
}
