import 'playback_state.dart';
import 'video_url.dart';

/// Whether the current core source ([filePath] at playback [status]) is safe to
/// announce to the room on a (re)connect.
///
/// A local file is always announceable (it's a real, valid source). A URL must
/// have actually opened — a still-`loading` or `error` link keeps `filePath`
/// set, but the load path announces a URL's real outcome itself, so a
/// connect/reconnect blip must not pre-announce a not-yet-playable or failed
/// link as if it had loaded.
bool canAnnounceOnConnect({
  required String? filePath,
  required PlaybackStatus status,
}) {
  if (filePath == null) return false;
  if (status == PlaybackStatus.error) return false;
  if (isHttpUrl(filePath) &&
      status != PlaybackStatus.playing &&
      status != PlaybackStatus.paused &&
      status != PlaybackStatus.ended) {
    return false;
  }
  return true;
}
