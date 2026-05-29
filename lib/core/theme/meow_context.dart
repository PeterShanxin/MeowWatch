import 'package:flutter/material.dart';

import 'meow_theme.dart';

/// Build a Material ThemeData for [id], carrying its MeowColors extension and a
/// dark ColorScheme seeded from the preset accent so stock Material widgets
/// stay coherent.
ThemeData themeDataFor(MeowThemeId id) {
  final c = id.colors;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: Brightness.dark,
    ),
    extensions: <ThemeExtension<dynamic>>[c],
  );
}

/// Ergonomic access to the active MeowColors: `context.meow.accent`.
extension MeowContext on BuildContext {
  MeowColors get meow => Theme.of(this).extension<MeowColors>()!;
}
