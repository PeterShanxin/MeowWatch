import 'package:flutter/material.dart';

import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/motion.dart';

/// Wraps [child] so it scales down a touch on press and lifts slightly on hover
/// — the shared "this is pressable" feel for buttons across the app. Fires
/// [onPressed] on tap.
///
/// Honors reduce motion: when on, there is no scale at all (the child stays a
/// normal, instantly-responsive tap target). The squash here is deliberately
/// tiny (a few percent) — this is the everyday press feel, not the one
/// [Motion.elasticPop] character beat.
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    this.onPressed,
    this.semanticLabel,
    this.pressedScale = 0.97,
    this.hoverScale = 1.02,
    super.key,
  });

  final Widget child;

  /// Tap callback. When null the control is disabled: no scale, no cursor, and
  /// taps do nothing.
  final VoidCallback? onPressed;

  final String? semanticLabel;

  /// Scale while held down (a ~2–3% squash by default).
  final double pressedScale;

  /// Scale while hovered with a mouse (a subtle lift).
  final double hoverScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  void _setHovered(bool v) {
    if (_hovered != v) setState(() => _hovered = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    final enabled = widget.onPressed != null;
    final target = (!enabled || reduce)
        ? 1.0
        : _pressed
            ? widget.pressedScale
            : _hovered
                ? widget.hoverScale
                : 1.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        // Press visual is driven off the raw pointer (zero latency) rather than
        // GestureDetector.onTapDown, which only fires after the ~100ms tap
        // deadline — that delay would make the squash feel laggy. The tap itself
        // (onPressed) still runs through GestureDetector so a drag-off cancels.
        child: Listener(
          onPointerDown: enabled ? (_) => _setPressed(true) : null,
          onPointerUp: enabled ? (_) => _setPressed(false) : null,
          onPointerCancel: enabled ? (_) => _setPressed(false) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onTapCancel: () => _setPressed(false),
            child: AnimatedScale(
              scale: target,
              duration: reduce ? Duration.zero : Motion.xfast,
              curve: Motion.standard,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
