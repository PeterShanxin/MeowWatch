/// Named opacity levels for standalone alpha applications. Global across themes.
/// `dim` mirrors MeowColors.textDim's alpha (0x99 ≈ 0.60) for consistency.
abstract final class Opacities {
  static const double dim = 0.60;
  static const double scrim = 0.50;
  static const double disabled = 0.38;
  static const double pressed = 0.12;
  static const double hover = 0.08;
}
