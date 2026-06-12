import 'playback_state.dart';

/// Whether the current core source ([filePath] at playback [status]) is safe to
/// (re)announce to the room on a connect/reconnect.
///
/// Only a source that has actually opened may be announced — `playing`,
/// `paused`, or `ended`. A still-`loading` or `error` source keeps `filePath`
/// set, but the load path announces a source's real outcome itself once it
/// settles, so a connect/reconnect blip must not pre-announce a not-yet-playable
/// or failed source as if it had loaded. This holds for local files and URLs
/// alike — a moved/unreadable file fails asynchronously the same way a bad link
/// does.
bool canAnnounceOnConnect({
  required String? filePath,
  required PlaybackStatus status,
}) {
  if (filePath == null) return false;
  return status == PlaybackStatus.playing ||
      status == PlaybackStatus.paused ||
      status == PlaybackStatus.ended;
}
