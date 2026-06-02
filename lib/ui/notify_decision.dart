/// Which notification sound (if any) a freshly-arrived chat message should play.
enum NotifyKind { none, primary, secondary }

/// Decide the sound for a new message. Order matters:
/// 1. our own message or a system/sync line is silent (the #57 fix);
/// 2. an unfocused window gets the loud primary;
/// 3. a focused window only sounds when the chat is collapsed AND the video is
///    playing — a quiet secondary so a message is felt without yanking the eye
///    off the video. Focused-with-chat-open, or paused, stays silent.
NotifyKind decideNotify({
  required bool isSystem,
  required bool isOwnMessage,
  required bool windowFocused,
  required bool chatCollapsed,
  required bool videoPlaying,
}) {
  if (isSystem || isOwnMessage) return NotifyKind.none;
  if (!windowFocused) return NotifyKind.primary;
  if (chatCollapsed && videoPlaying) return NotifyKind.secondary;
  return NotifyKind.none;
}
