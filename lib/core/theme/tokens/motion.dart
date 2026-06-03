import 'package:flutter/animation.dart';

/// Animation speeds + easings. Global across themes.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve symmetric = Curves.easeInOut;
}
