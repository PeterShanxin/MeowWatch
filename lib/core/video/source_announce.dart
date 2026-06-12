import 'playback_state.dart';

/// Whether the room should be (re)announced the current source on a
/// connect/reconnect.
///
/// Gated on the source the load path actually *accepted* ([acceptedPath]), not
/// on the live playback state — because the two ambiguous-looking states can't
/// be told apart from [status] alone: a valid live stream stays `paused` with no
/// duration (accepted), and the transient tick before an async error also looks
/// `paused` with no duration (not accepted). Tracking the accepted path settles
/// it: announce only when the current source *is* the accepted one and it hasn't
/// since errored.
bool canAnnounceOnConnect({
  required String? currentPath,
  required String? acceptedPath,
  required PlaybackStatus status,
}) {
  if (currentPath == null || acceptedPath == null) return false;
  if (status == PlaybackStatus.error) return false;
  return currentPath == acceptedPath;
}
