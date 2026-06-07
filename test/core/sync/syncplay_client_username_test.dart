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

  // Regression for #93: a reconnect against a lingering ghost of our own
  // dropped session makes the server hand back a deduped name ("meow_"). The
  // PREVIOUS code adopted that name AND reused it for the next Hello, so each
  // reconnect added another "_" (meow -> meow_ -> meow__ …). The fix keeps the
  // originally requested name for every Hello.
  test('reconnect re-requests the original name, not the assigned suffix',
      () async {
    final client = SyncplayClient();
    client.debugSeedIdentity('meow');

    // Server dedupes against our ghost and assigns a suffixed name.
    client.debugHandleMessage(const HelloMessage(username: 'meow_'));
    expect(client.debugRequestedUsername, 'meow',
        reason: 'adopting the assigned name must not change what we request');

    // The reconnect Hello must still ask for the clean original name.
    client.debugSendHello();
    final hellos = client.debugSentMessages
        .where((m) => m.containsKey('Hello'))
        .map((m) => (m['Hello'] as Map)['username'])
        .toList();
    expect(hellos.last, 'meow');

    await client.dispose();
  });

  test('the suffix never compounds across repeated reconnects', () async {
    final client = SyncplayClient();
    client.debugSeedIdentity('meow');

    // Three drop/reconnect cycles, each time the server suffixing again.
    for (final assigned in ['meow_', 'meow_', 'meow_']) {
      client.debugSendHello();
      client.debugHandleMessage(HelloMessage(username: assigned));
    }

    final hellos = client.debugSentMessages
        .where((m) => m.containsKey('Hello'))
        .map((m) => (m['Hello'] as Map)['username'])
        .toList();
    // Every Hello asked for the clean name — no "meow__", "meow___", etc.
    expect(hellos, everyElement('meow'));

    await client.dispose();
  });

  // The roster after a ghosted reconnect lists the ghost under the ORIGINAL
  // name ("meow") while the server now calls us "meow_". The ghost is still us —
  // it must not surface as a peer, or its file/leave corrupts peer state (#93).
  test('the ghost of self (original name) is not treated as a peer', () async {
    final client = SyncplayClient();
    final peers = <String>[];
    final peerFiles = <PeerFile>[];
    final pSub = client.presence.listen((e) => peers.add(e.username));
    final fSub = client.peerFile.listen(peerFiles.add);

    client.debugSeedIdentity('meow');
    client.debugHandleMessage(const HelloMessage(username: 'meow_'));

    // Roster: our ghost (meow, carrying OUR file), us (meow_), and the friend.
    client.debugHandleMessage(const RosterMessage(
      ['meow', 'meow_', 'lin'],
      files: [
        PeerFile(username: 'meow', name: 'mine.mkv'),
        PeerFile(username: 'lin', name: 'friend.mkv'),
      ],
    ));
    await Future<void>.delayed(Duration.zero);

    // Only the genuine friend is a peer; neither self-name leaks through.
    expect(peers, ['lin']);
    expect(peerFiles.map((f) => f.username), ['lin']);

    await pSub.cancel();
    await fSub.cancel();
    await client.dispose();
  });

  test('a ghost-self "left" event does not reach the UI', () async {
    final client = SyncplayClient();
    final left = <String>[];
    final sub = client.presence
        .where((e) => e.kind == PresenceKind.left)
        .listen((e) => left.add(e.username));

    client.debugSeedIdentity('meow');
    client.debugHandleMessage(const HelloMessage(username: 'meow_'));

    // Server reaps the ghost: a Set with our ORIGINAL name leaving.
    client.debugHandleMessage(const PresenceMessage([
      PresenceEvent(username: 'meow', kind: PresenceKind.left),
    ]));
    await Future<void>.delayed(Duration.zero);

    // The ghost-self "left" must be swallowed — it must not clear a real peer's
    // file downstream (#93).
    expect(left, isEmpty);

    await sub.cancel();
    await client.dispose();
  });
}
