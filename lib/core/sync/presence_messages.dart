import 'peer_state.dart';

/// Chat line announced when the local link drops from a live connection.
const String connectionLostMessage = 'Connection lost — reconnecting…';

/// Chat line announced when the local link returns after a reconnect.
const String reconnectedToRoomMessage = 'Reconnected to room.';

/// Build the chat system line shown when a peer deliberately leaves vs drops.
String peerDepartureMessage({
  required String username,
  required bool clean,
}) =>
    clean ? '$username left the room.' : '$username lost connection.';

/// Build the chat system line shown when a peer joins for the first time or
/// rejoins after a detected drop.
String peerJoinMessage({
  required String username,
  required bool reconnected,
}) =>
    reconnected ? '$username reconnected.' : '$username joined the room.';

/// True when the link just dropped from a live connection — the moment to
/// announce a connection loss. Gated to the `connected → reconnecting` edge so
/// the repeated backoff attempts (`handshaking → reconnecting`) don't
/// re-announce on every retry.
bool isConnectionDrop({
  required SyncConnectionStatus prev,
  required SyncConnectionStatus next,
}) =>
    next == SyncConnectionStatus.reconnecting &&
    prev == SyncConnectionStatus.connected;

/// True when we've arrived back at [SyncConnectionStatus.connected] while a
/// reconnect was underway. [wasReconnecting] is a latch the caller sets on a
/// drop and clears here — needed because the reconnect path passes through an
/// intermediate `handshaking` state, so a simple `prev` comparison can't see
/// that a reconnect was in progress. A first connect never sets the latch, so
/// the initial login stays silent.
bool isReconnectSuccess({
  required bool wasReconnecting,
  required SyncConnectionStatus next,
}) =>
    wasReconnecting && next == SyncConnectionStatus.connected;

/// The name of our own lingering ghost session to silence on its imminent
/// departure, or null if there is none.
///
/// When a [reconnected] login comes back with an [assignedName] the server
/// suffixed away from our [chosenName] ("meowPEOW" → "meowPEOW_"), our *prior*
/// dropped session is still holding the clean name and is about to be reaped.
/// Its `left` event would otherwise surface as a peer "lost connection." — but
/// the name is our own, which confused users (#93 field report). We only treat
/// the clean name as a ghost on a *reconnect* with an *actual* suffix: on a
/// first connect a suffix means a genuinely different namesake, whose departure
/// must still show. This only silences the one departure line; it never hides a
/// peer's presence or file.
String? ownGhostNameOnReconnect({
  required bool reconnected,
  required String chosenName,
  required String? assignedName,
}) =>
    (reconnected && assignedName != null && assignedName != chosenName)
        ? chosenName
        : null;

/// True when [departedAt] is non-null and falls within [window] of [now],
/// meaning a peer's departure is recent enough to be treated as a reconnect
/// rather than a fresh join.
bool isPeerReconnect({
  DateTime? departedAt,
  required DateTime now,
  Duration window = const Duration(seconds: 60),
}) =>
    departedAt != null && now.difference(departedAt) <= window;
