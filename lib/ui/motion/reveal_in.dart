import 'package:flutter/material.dart';

import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/motion.dart';

/// Fades + rises [child] into view once, on first mount. The everyday "this
/// just appeared" enter used by the launch reveal's lobby content and the
/// gallery demos. Honors reduce motion: when on, [child] is shown instantly,
/// fully present, with no rise and no overshoot.
class RevealIn extends StatefulWidget {
  const RevealIn({
    required this.child,
    this.delay = Duration.zero,
    this.offset = 16,
    this.duration = Motion.base,
    this.overshoot = false,
    super.key,
  });

  final Widget child;

  /// How long to wait after mount before starting (for cascades).
  final Duration delay;

  /// Logical pixels the child rises from (translate-up distance).
  final double offset;

  final Duration duration;

  /// When true, the rise settles with the gentle [Motion.springy] overshoot;
  /// otherwise [Motion.emphasized].
  final bool overshoot;

  @override
  State<RevealIn> createState() => _RevealInState();
}

class _RevealInState extends State<RevealIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  // Built once and disposed with the state. A CurvedAnimation attaches a status
  // listener to its parent controller, so rebuilding it on every build() (e.g.
  // a theme change while the reveal is mounted) would leak listeners and retain
  // the old curves on _c until the whole widget disposes.
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _c,
    curve: widget.overshoot ? Motion.springy : Motion.emphasized,
  );
  bool _kicked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kicked) return;
    _kicked = true;
    if (context.reduceMotion) {
      _c.value = 1; // instant present
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          // Opacity must stay in [0,1] even when springy overshoots past 1.
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
