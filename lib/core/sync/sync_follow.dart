import 'package:flutter/foundation.dart';

import 'peer_state.dart';
import 'syncplay_constants.dart';

/// What the local player should do in response to a relayed global room state.
@immutable
class FollowAction {
  const FollowAction.none()
      : shouldApply = false,
        position = Duration.zero,
        paused = true;

  const FollowAction.apply({required this.position, required this.paused})
      : shouldApply = true;

  final bool shouldApply;
  final Duration position;
  final bool paused;
}

/// Decide whether to follow the room's [global] playstate, mirroring upstream
/// Syncplay's `_changePlayerStateAccordingToGlobalState`. The two rules that
/// stop clients fighting:
///   1. A play/pause flip is detected by comparing the global paused flag to
///      our own local paused flag — so once we match, steady heartbeats do
///      nothing, and our own change (already reflected locally) never echoes.
///   2. Seeks and drift-rewinds are ignored when the change was [setBy] us.
/// Position is only corrected on an explicit peer seek, or when our player has
/// run AHEAD of the room by more than [rewindThreshold] (one-directional).
FollowAction decideFollow({
  required PeerPlayState global,
  required bool localPaused,
  required Duration localPosition,
  required String username,
  Duration rewindThreshold = SyncplayConstants.rewindThreshold,
}) {
  final isSelf = global.setBy != null && global.setBy == username;

  // 1. Pause/play flip — compare to local, so self-changes (already applied
  //    locally) produce no action.
  if (global.paused != localPaused) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  // 2. Explicit seek by someone else.
  if (global.doSeek && !isSelf) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  // 3. Rewind only if WE are ahead of the room beyond the threshold.
  final aheadBy = localPosition - global.position;
  if (!global.doSeek && !isSelf && aheadBy > rewindThreshold) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  return const FollowAction.none();
}
