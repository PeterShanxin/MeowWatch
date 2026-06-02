/// Pure visibility logic for the idle-auto-hide behavior (issues #5 / #18),
/// split out from `HomeScreen` so the branch table can be unit-tested headless.
///
/// While a video is playing and the user has been idle for a few seconds, the
/// overlays get out of the way: the player controls, the top-left gear, and the
/// emoji reaction bar fade out, and the open chat card dims (or stays put, per
/// the user's "Dim chat when idle" setting). Any interaction — or playback
/// pausing — restores everything immediately.
library;

/// Opacity for the chat overlay (card or collapsed tab) given the idle state.
///
/// - Not idle → fully visible (`1.0`).
/// - Idle + collapsed → fully hidden (`0.0`), unless `hasUnread`, in which case
///   the minimized tab/badge stays fully visible (`1.0`) so an unread
///   notification survives idle and deep idle (issues #5 / #43).
/// - Idle + expanded + auto-dim on:
///   - `hasUnread` → fully visible (`1.0`) if `wakeToFullyVisible`, else a faint
///     ghost (`0.1`); deep idle does not hide it while unread (#43).
///   - no unread → faint ghost (`0.1`) so it stays out of the way without
///     vanishing (issue #18), then fully hidden (`0.0`) once idle persists into
///     deep idle (issue #34).
/// - Idle + expanded + auto-dim off → fully visible (`1.0`): the user opted to
///   keep chat always visible (respected even in deep idle).
///
/// `hasUnread` is whether the chat has unread messages; `wakeToFullyVisible` is
/// the user's "Fully wake chat on message" setting (expanded card only —
/// a collapsed unread tab is always fully visible).
///
/// The dimmed (non-deep) ghost uses [kChatIdleGhostOpacity] — faint enough to
/// stay out of the way, but readable. In *deep* idle the expanded card fades
/// fully out even with unread messages, so a wake-on-message brighten doesn't
/// leave it lingering on screen forever; a fresh message re-arms the deep-idle
/// countdown (see HomeScreen), so it wakes and then settles back out.
double chatOverlayOpacity({
  required bool idle,
  required bool collapsed,
  required bool autoDim,
  bool deepIdle = false,
  bool hasUnread = false,
  bool wakeToFullyVisible = false,
  double ghostOpacity = kChatIdleGhostOpacity,
}) {
  if (!idle) return 1.0;

  if (collapsed) {
    // The minimized unread tab/badge survives idle and deep idle so a missed
    // message stays flagged (#43); without unread it hides.
    return hasUnread ? 1.0 : 0.0;
  }

  if (!autoDim) return 1.0;

  // Deep idle wins: the expanded card fades fully out even while unread.
  if (deepIdle) return 0.0;

  if (hasUnread) {
    return wakeToFullyVisible ? 1.0 : ghostOpacity;
  }

  return ghostOpacity;
}

/// Default opacity of the dimmed-but-not-hidden chat card on first idle. Raised
/// to stay readable; the user can tune it via the gear slider, clamped to
/// [kChatIdleDimMin]–[kChatIdleDimMax].
const double kChatIdleGhostOpacity = 0.5;

/// User-tunable bounds for the idle dim opacity (gear slider).
const double kChatIdleDimMin = 0.15;
const double kChatIdleDimMax = 0.95;

/// Opacity for the secondary overlays (gear button, reaction bar) that simply
/// fade fully out when idle and back in otherwise.
double overlayOpacity({required bool idle}) => idle ? 0.0 : 1.0;
