import 'package:flutter/animation.dart';

/// Animation speeds + easings. Global across themes.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  /// Per-item delay when a list cascades items in one after another (the
  /// "Continue watching" staggered reflow). Small enough to read as one
  /// rippling motion rather than a sequence of separate animations.
  static const Duration stagger = Duration(milliseconds: 55);

  /// The cold-start launch reveal's total timeline. The longest token, used
  /// nowhere else — the splash wash → wordmark → dissolve all fit inside it.
  static const Duration reveal = Duration(milliseconds: 800);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve symmetric = Curves.easeInOut;

  /// Material 3 "emphasized" — the hero enter for big, expressive moves
  /// (the launch reveal, panels). Slow-in/slow-out with a confident middle.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// The hero *exit* counterpart: starts quick, eases out — used when a hero
  /// element leaves (the reveal's wash dissolving away).
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// The single "character" curve: a mild overshoot that settles. Used sparingly
  /// for the one playful beat (the mark settling in). Deliberately gentle, not
  /// elastic.
  static const Curve springy = Cubic(0.34, 1.26, 0.64, 1.0);
}
