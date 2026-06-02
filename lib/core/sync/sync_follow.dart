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

  // Never follow a state we ourselves set. During the brief window after we
  // change play/pause but before the server acknowledges, the server keeps
  // echoing the OLD global state stamped with our name; applying it would undo
  // our own change and start the ping-pong fight.
  if (isSelf) return const FollowAction.none();

  // 1. Pause/play flip — compare to local, so once we match, steady
  //    heartbeats produce no action.
  if (global.paused != localPaused) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  // 2. Explicit seek by someone else.
  if (global.doSeek && !isSelf) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  // 3. Rewind only if WE are ahead of the room beyond the threshold AND a real
  //    peer set this position. The server's empty-room default state has
  //    position 0 and no [setBy]; without this guard, when both clients drop
  //    and rejoin together (one PC, one network blip → the room empties and
  //    resets to 0), each is "far ahead" of that phantom 0 and rewinds to it —
  //    dragging a mid-film session back to 00:00. A genuine drift-rewind always
  //    has the peer's name on it, so requiring [setBy] loses nothing real.
  final aheadBy = localPosition - global.position;
  if (!global.doSeek &&
      !isSelf &&
      global.setBy != null &&
      aheadBy > rewindThreshold) {
    return FollowAction.apply(position: global.position, paused: global.paused);
  }

  return const FollowAction.none();
}
