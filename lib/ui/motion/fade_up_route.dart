import 'package:flutter/material.dart';

import '../../core/theme/tokens/motion.dart';

/// A forward page push that fades the page built by [builder] in while it rises
/// from slightly below, on the [Motion.emphasized] curve; reversed on pop. When
/// [reduceMotion] is true the transition is an instant cut (no fade, no rise) —
/// pass `context.reduceMotion` at the push site.
///
/// The rise uses a small fractional slide (4% of the page height) so it reads as
/// a gentle lift at any window size without per-pixel math.
///
/// [builder] (not a pre-built widget) so the page rebuilds when the host above
/// the navigator rebuilds — Flutter re-invokes the page builder on a route's
/// `changedExternalState`. That keeps a captured `HomeScreen` tracking live app
/// state (e.g. the current theme the in-room gear switches), exactly as the
/// `MaterialPageRoute(builder:)` it replaced did.
PageRouteBuilder<T> fadeUpRoute<T>({
  required WidgetBuilder builder,
  required bool reduceMotion,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotion ? Duration.zero : Motion.expressive,
    reverseTransitionDuration: reduceMotion ? Duration.zero : Motion.base,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
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
