import 'package:flutter/animation.dart';

/// Animation speeds + easings. Global across themes.
abstract final class Motion {
  /// The snappiest token — press-down / hover feedback, where any perceptible
  /// delay would feel laggy. Used by [PressableScale]'s press scale.
  static const Duration xfast = Duration(milliseconds: 80);

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  /// A longer, expressive entrance/transition — the cold-start lobby card
  /// cascade and the room push. Slower than [slow] so the rise reads as a
  /// graceful, premium move rather than a snap (Material 3 "emphasized"
  /// large-transition range). Reduce motion drops it to an instant.
  static const Duration expressive = Duration(milliseconds: 440);

  /// Per-item delay when a list cascades items in one after another (the
  /// "Continue watching" staggered reflow). Small enough to read as one
  /// rippling motion rather than a sequence of separate animations.
  static const Duration stagger = Duration(milliseconds: 55);

  /// The cold-start launch reveal's total timeline. The longest token, used
  /// nowhere else — the splash wash → mark → wordmark → a readable dwell →
  /// dissolve all fit inside it. Long enough that the late tip line holds still
  /// for ~0.9s before anything fades, so it's actually readable (it's skippable
  /// on any click/key, so the length never traps an impatient user).
  static const Duration reveal = Duration(milliseconds: 2800);

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

  /// The one true squash-&-stretch beat: a stronger overshoot than [springy],
  /// scoped to the floating paw-reaction burst (the only place the app lets
  /// itself bounce). Never reuse this for everyday UI — that's what [springy]
  /// and [standard] are for.
  static const Curve elasticPop = Cubic(0.2, 1.5, 0.4, 1.0);
}
