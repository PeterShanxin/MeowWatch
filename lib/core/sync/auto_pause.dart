import 'package:flutter/foundation.dart';

/// Whether the co-watch session is currently in sync: connected to the room
/// AND at least one friend is present. Either condition failing means you'd be
/// watching alone, out of sync.
@immutable
class SyncHealth {
  const SyncHealth({required this.connected, required this.hasPeer});

  final bool connected;
  final bool hasPeer;

  bool get healthy => connected && hasPeer;
}

/// Should the local video auto-pause right now?
///
/// Fires only on the *edge* from healthy to unhealthy while the video is
/// playing — so a deliberate play while already alone is respected and never
/// re-paused. On restore (unhealthy -> healthy) it does nothing: the video
/// stays paused until the watchers hit play together.
bool decideAutoPause({
  required bool wasHealthy,
  required bool nowHealthy,
  required bool isPlaying,
}) {
  return wasHealthy && !nowHealthy && isPlaying;
}
