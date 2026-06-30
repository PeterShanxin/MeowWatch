import 'package:flutter/material.dart';

import '../core/theme/reduce_motion.dart';
import '../core/theme/tokens/motion.dart';

/// An icon button that fires [onPressed] on the raw pointer-DOWN, with zero
/// gesture-arena latency, and absorbs tap + double-tap from any ancestor
/// [GestureDetector]. It also squashes a touch on press (the shared
/// [PressableScale]-style feel) — driven off the same pointer-down so the press
/// visual never adds latency.
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
class InstantTapIcon extends StatefulWidget {
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
  State<InstantTapIcon> createState() => _InstantTapIconState();
}

class _InstantTapIconState extends State<InstantTapIcon> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        // Restore the keyboard activation the replaced IconButton provided:
        // focusable, and Enter/Space (→ ActivateIntent) fire onPressed.
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: Listener(
          onPointerDown: (_) {
            widget.onPressed();
            if (!reduce) _setPressed(true);
          },
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // No-ops: present only to win these gestures over the ancestor.
            onTap: () {},
            onDoubleTap: () {},
            child: AnimatedScale(
              scale: (_pressed && !reduce) ? 0.92 : 1.0,
              duration: reduce ? Duration.zero : Motion.xfast,
              curve: Motion.standard,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Center(child: Icon(widget.icon, color: widget.color)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
