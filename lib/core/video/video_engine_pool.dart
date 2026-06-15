import 'package:media_kit/media_kit.dart';

import 'media_kit_video_core.dart';

/// Process-lifetime holder for the heavyweight libmpv engines so that leaving a
/// room never tears them down.
///
/// **Why this exists (issue #137).** media_kit's [Player.dispose] runs libmpv's
/// teardown on the root isolate — i.e. Flutter's UI thread. When players are
/// created and destroyed repeatedly on Windows, `mpv_terminate_destroy` can
/// *deadlock* there and never return, permanently freezing whatever screen was
/// just shown (you leave a room, land on Connect, and nothing is clickable until
/// the app is killed). The cost is GPU/driver dependent, which is why it strikes
/// one machine and not another. This is a known media_kit failure mode, and the
/// established remedy is to **reuse** a player instead of disposing and
/// recreating it (media-kit/media-kit#857).
///
/// So MeowWatch keeps exactly one video engine and one notification-sound engine
/// for the whole process. [HomeScreen] borrows them on entry and, on leave,
/// merely *empties* them ([MediaKitVideoCore.reset] / [Player.stop]) rather than
/// disposing — the deadlock-prone teardown path is never taken during the app's
/// life. The OS reclaims the engines when the process exits, so there is
/// deliberately no `disposeAll`: a graceful libmpv terminate is exactly the call
/// we are avoiding.
///
/// Created lazily on first use (the first room joined) so a session that never
/// enters a room — and tests that never do — never spin up libmpv.
class VideoEnginePool {
  VideoEnginePool._();

  /// The single shared pool. Mirrors the existing process-global pattern used by
  /// `appCloseHook`; there is only ever one active room (one window) at a time.
  static final VideoEnginePool instance = VideoEnginePool._();

  MediaKitVideoCore? _videoCore;
  Player? _audioPlayer;

  /// The shared video engine. Reused across rooms; emptied via
  /// [MediaKitVideoCore.reset] on leave, never disposed.
  MediaKitVideoCore get videoCore => _videoCore ??= MediaKitVideoCore();

  /// The shared notification-sound engine. Reused across rooms; emptied via
  /// [Player.stop] on leave, never disposed.
  Player get audioPlayer => _audioPlayer ??= Player();
}
