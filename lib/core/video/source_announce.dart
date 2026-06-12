import 'playback_state.dart';

/// Whether the current core [state] is safe to (re)announce to the room on a
/// connect/reconnect.
///
/// Only a confirmed open ([isPlaybackOpen]) may be announced — never a source
/// still `loading`, the transient `paused` tick before an async error, or an
/// `error`. The load path announces a source's real outcome itself once it
/// settles, so a connect/reconnect blip must not pre-announce a not-yet-playable
/// or failed source as if it had loaded. Holds for local files and URLs alike.
bool canAnnounceOnConnect(PlaybackState state) =>
    state.filePath != null && isPlaybackOpen(state);
