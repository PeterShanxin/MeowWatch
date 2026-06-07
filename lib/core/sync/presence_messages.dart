import 'peer_state.dart';

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

/// Return the system chat line for a local connection-state transition, or null
/// if the transition needs no announcement.
///
/// Fires "Reconnected" only when coming back from [reconnecting] (not from a
/// fresh first connect), so the initial login is silent.
String? localConnectionLine({
  required SyncConnectionStatus prev,
  required SyncConnectionStatus next,
}) {
  if (next == SyncConnectionStatus.connected &&
      prev == SyncConnectionStatus.reconnecting) {
    return 'Reconnected to room.';
  }
  if (next == SyncConnectionStatus.reconnecting &&
      prev == SyncConnectionStatus.connected) {
    return 'Connection lost — reconnecting…';
  }
  return null;
}

/// True when [departedAt] is non-null and falls within [window] of [now],
/// meaning a peer's departure is recent enough to be treated as a reconnect
/// rather than a fresh join.
bool isPeerReconnect({
  DateTime? departedAt,
  required DateTime now,
  Duration window = const Duration(seconds: 60),
}) =>
    departedAt != null && now.difference(departedAt) <= window;
