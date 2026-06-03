import 'package:flutter/painting.dart';

/// Drop shadows. Geometry is global; color derives from the active theme's
/// scrim so shadows read correctly on every theme. Pass `context.meow.scrim`.
abstract final class Shadows {
  static List<BoxShadow> card(Color scrim) => [
        BoxShadow(
          color: scrim.withValues(alpha: 0.45),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> overlay(Color scrim) => [
        BoxShadow(
          color: scrim.withValues(alpha: 0.60),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
