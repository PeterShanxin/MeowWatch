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

  static const Curve standard = Curves.easeOutCubic;
  static const Curve symmetric = Curves.easeInOut;
}
