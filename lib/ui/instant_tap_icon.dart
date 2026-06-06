import 'package:flutter/material.dart';

/// An icon button that fires [onPressed] on the raw pointer-DOWN, with zero
/// gesture-arena latency, and absorbs tap + double-tap from any ancestor
/// [GestureDetector].
///
/// MeowWatch's video surface wraps everything in a GestureDetector with onTap
/// (play/pause) and onDoubleTap (fullscreen). Those recognizers hold the gesture
/// arena open ~300ms waiting for a possible second tap, so a normal
/// [IconButton] nested inside feels laggy — its onPressed can't fire until the
/// arena resolves. Routing through [Listener.onPointerDown] sidesteps the arena
/// entirely (instant), while the no-op [GestureDetector] tap/double-tap claim
/// those gestures for this deeper detector so the ancestor never toggles
/// play/pause or fullscreen when you click the button.
///
/// Keyboard parity with the [IconButton] it replaces is kept via
/// [FocusableActionDetector]: the button is focusable and Enter/Space activate
/// it (mapped from [ActivateIntent]).
class InstantTapIcon extends StatelessWidget {
  const InstantTapIcon({
    required this.icon,
    required this.onPressed,
    this.color,
    this.semanticLabel,
    this.size = 48,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final String? semanticLabel;

  /// Square tap-target size (matches the Material default of 48).
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: FocusableActionDetector(
        // Restore the keyboard activation the replaced IconButton provided:
        // focusable, and Enter/Space (→ ActivateIntent) fire onPressed.
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onPressed();
              return null;
            },
          ),
        },
        child: Listener(
          onPointerDown: (_) => onPressed(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // No-ops: present only to win these gestures over the ancestor.
            onTap: () {},
            onDoubleTap: () {},
            child: SizedBox(
              width: size,
              height: size,
              child: Center(child: Icon(icon, color: color)),
            ),
          ),
        ),
      ),
    );
  }
}
