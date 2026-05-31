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
/// - Idle + collapsed → fully hidden (`0.0`): the minimized tab/icon auto-hides
///   (issue #5).
/// - Idle + expanded + auto-dim on → faint ghost (`0.1`) so it stays out of the
///   way without vanishing (issue #18), then fully hidden (`0.0`) once idle
///   persists into deep idle (issue #34).
/// - Idle + expanded + auto-dim off → fully visible (`1.0`): the user opted to
///   keep chat always visible (respected even in deep idle).
double chatOverlayOpacity({
  required bool idle,
  required bool collapsed,
  required bool autoDim,
  bool deepIdle = false,
}) {
  if (!idle) return 1.0;
  if (collapsed) return 0.0;
  if (!autoDim) return 1.0;
  return deepIdle ? 0.0 : 0.1;
}

/// Opacity for the secondary overlays (gear button, reaction bar) that simply
/// fade fully out when idle and back in otherwise.
double overlayOpacity({required bool idle}) => idle ? 0.0 : 1.0;
