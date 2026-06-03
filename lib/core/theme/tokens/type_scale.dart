import 'package:flutter/painting.dart' show FontWeight;

/// Type scale: font sizes + weights only (no color/family — those come from the
/// active theme via context.meowText). Global across themes.
abstract final class TypeScale {
  static const double caption = 11;
  static const double body = 13;
  static const double label = 15;
  static const double title = 18;
  static const double heading = 24;
  static const double display = 30;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}
