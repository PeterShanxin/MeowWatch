/// Which notification sound (if any) a freshly-arrived chat message should play.
enum NotifyKind { none, primary, secondary }

/// Decide the sound for a new message. Order matters:
/// 1. our own message or a system/sync line is silent (the #57 fix);
/// 2. an unfocused window gets the loud primary;
/// 3. a focused window only sounds when the chat can't be read right now AND the
///    video is playing — a quiet secondary so a message is felt without yanking
///    the eye off the video. "Can't be read" means either the chat is collapsed,
///    or the expanded card has been faded away by idle (the idle dim, or the
///    deep-idle invisible state). A focused window with the chat open and
///    readable, or paused, stays silent.
NotifyKind decideNotify({
  required bool isSystem,
  required bool isOwnMessage,
  required bool windowFocused,
  required bool chatCollapsed,
  required bool chatDimmedByIdle,
  required bool videoPlaying,
}) {
  if (isSystem || isOwnMessage) return NotifyKind.none;
  if (!windowFocused) return NotifyKind.primary;
  if (videoPlaying && (chatCollapsed || chatDimmedByIdle)) {
    return NotifyKind.secondary;
  }
  return NotifyKind.none;
}
