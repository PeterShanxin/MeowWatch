import 'package:flutter/material.dart';

/// Carries the app-level "reduce motion" preference down the tree. When on,
/// motion primitives degrade to an instant present (no rise, no overshoot).
/// Set app-wide from the in-app Settings "Reduce motion" toggle (via a scope in
/// `MaterialApp.builder`), and also by the design gallery's preview toggle.
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
