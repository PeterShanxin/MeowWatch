import 'package:flutter/material.dart';

/// Forces "reduce motion" on for a subtree, so motion primitives degrade to an
/// instant present (no rise, no overshoot). There is no in-app toggle: in normal
/// use reduce motion comes from the OS "reduce animations" accessibility setting
/// (read via [ReduceMotionContext.reduceMotion]). This scope exists to force the
/// degraded form regardless of the OS — used by tests.
class ReduceMotionScope extends InheritedWidget {
  const ReduceMotionScope({
    required this.reduceMotion,
    required super.child,
    super.key,
  });

  final bool reduceMotion;

  static bool of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ReduceMotionScope>();
    return scope?.reduceMotion ?? false;
  }

  @override
  bool updateShouldNotify(ReduceMotionScope old) =>
      old.reduceMotion != reduceMotion;
}

/// `context.reduceMotion` — true when this app's scope says so OR the OS
/// "reduce animations" accessibility setting is on. Every motion primitive
/// reads this so no screen has to special-case it.
extension ReduceMotionContext on BuildContext {
  bool get reduceMotion =>
      ReduceMotionScope.of(this) || MediaQuery.disableAnimationsOf(this);
}
