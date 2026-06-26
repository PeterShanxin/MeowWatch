import 'package:flutter/material.dart';

import '../../core/theme/tokens/motion.dart';

/// A forward page push that fades [page] in while it rises from slightly below,
/// on the [Motion.emphasized] curve; reversed on pop. When [reduceMotion] is
/// true the transition is an instant cut (no fade, no rise) — pass
/// `context.reduceMotion` at the push site.
///
/// The rise uses a small fractional slide (4% of the page height) so it reads as
/// a gentle lift at any window size without per-pixel math.
PageRouteBuilder<T> fadeUpRoute<T>({
  required Widget page,
  required bool reduceMotion,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotion ? Duration.zero : Motion.expressive,
    reverseTransitionDuration: reduceMotion ? Duration.zero : Motion.base,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final t = animation.drive(CurveTween(curve: Motion.emphasized));
      return FadeTransition(
        opacity: t,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(t),
          child: child,
        ),
      );
    },
  );
}
