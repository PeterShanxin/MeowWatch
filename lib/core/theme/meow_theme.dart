import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// All MeowWatch-specific colors + presentation flags, carried on ThemeData as
/// a ThemeExtension. Read it via `context.meow` (see meow_context.dart).
@immutable
class MeowColors extends ThemeExtension<MeowColors> {
  const MeowColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textDim,
    required this.border,
    required this.myBubble,
    required this.peerBubble,
    required this.scrim,
    required this.online,
    required this.error,
    this.backgroundGradient,
    this.glassBlur = 0,
    this.titleFontFamily,
  });

  final Color background;
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textDim;
  final Color border;
  final Color myBubble;
  final Color peerBubble;

  /// Base black for shadows/scrims; widgets apply their own opacity.
  final Color scrim;

  /// "Most recent / online" status dot.
  final Color online;

  /// Error / failure accent — the load-error icon, inline validation text, and
  /// any other "something went wrong" affordance. Per-theme so it never clashes.
  final Color error;

  /// Non-null = paint the window background as this gradient instead of [background].
  final Gradient? backgroundGradient;

  /// >0 = frost the chat card / control bar with a BackdropFilter of this sigma.
  final double glassBlur;

  /// Non-null = render titles / chat header in this font family (serif for Noir).
  final String? titleFontFamily;

  static const cozy = MeowColors(
    background: Color(0xFF1A1410),
    surface: Color(0xF2241B14),
    accent: Color(0xFFD4A574),
    textPrimary: Color(0xFFF5E6D3),
    textDim: Color(0x99F5E6D3),
    border: Color(0x55D4A574),
    myBubble: Color(0x33D4A574),
    peerBubble: Color(0x55241B14),
    scrim: Color(0xFF000000),
    online: Color(0xFF7BC47F),
    error: Color(0xFFE08A7D),
  );

  static const noir = MeowColors(
    background: Color(0xFF000000),
    surface: Color(0xF50C0C0C),
    accent: Color(0xFFD4AF37),
    textPrimary: Color(0xFFECECEC),
    textDim: Color(0x99ECECEC),
    border: Color(0x38D4AF37),
    myBubble: Color(0x29D4AF37),
    peerBubble: Color(0x0FFFFFFF),
    scrim: Color(0xFF000000),
    online: Color(0xFF7BC47F),
    error: Color(0xFFD96E6E),
    titleFontFamily: 'serif',
  );

  static const aurora = MeowColors(
    background: Color(0xFF1E2A4A),
    surface: Color(0x1AFFFFFF),
    accent: Color(0xFF7DF9C2),
    textPrimary: Color(0xFFF0F4FF),
    textDim: Color(0xA6F0F4FF),
    border: Color(0x38FFFFFF),
    myBubble: Color(0x47A78BFA),
    peerBubble: Color(0x1AFFFFFF),
    scrim: Color(0xFF000000),
    online: Color(0xFF7DF9C2),
    error: Color(0xFFFF8FA3),
    backgroundGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2A1B4D), Color(0xFF1E3A5F), Color(0xFF0E3A4A)],
    ),
    glassBlur: 12,
  );

  @override
  MeowColors copyWith({
    Color? background,
    Color? surface,
    Color? accent,
    Color? textPrimary,
    Color? textDim,
    Color? border,
    Color? myBubble,
    Color? peerBubble,
    Color? scrim,
    Color? online,
    Color? error,
    Gradient? backgroundGradient,
    double? glassBlur,
    String? titleFontFamily,
  }) {
    return MeowColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textDim: textDim ?? this.textDim,
      border: border ?? this.border,
      myBubble: myBubble ?? this.myBubble,
      peerBubble: peerBubble ?? this.peerBubble,
      scrim: scrim ?? this.scrim,
      online: online ?? this.online,
      error: error ?? this.error,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      glassBlur: glassBlur ?? this.glassBlur,
      titleFontFamily: titleFontFamily ?? this.titleFontFamily,
    );
  }

  @override
  MeowColors lerp(covariant ThemeExtension<MeowColors>? other, double t) {
    if (other is! MeowColors) return this;
    return MeowColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      border: Color.lerp(border, other.border, t)!,
      myBubble: Color.lerp(myBubble, other.myBubble, t)!,
      peerBubble: Color.lerp(peerBubble, other.peerBubble, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      online: Color.lerp(online, other.online, t)!,
      error: Color.lerp(error, other.error, t)!,
      backgroundGradient:
          Gradient.lerp(backgroundGradient, other.backgroundGradient, t),
      glassBlur: lerpDouble(glassBlur, other.glassBlur, t) ?? glassBlur,
      titleFontFamily: t < 0.5 ? titleFontFamily : other.titleFontFamily,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MeowColors &&
      other.background == background &&
      other.surface == surface &&
      other.accent == accent &&
      other.textPrimary == textPrimary &&
      other.textDim == textDim &&
      other.border == border &&
      other.myBubble == myBubble &&
      other.peerBubble == peerBubble &&
      other.scrim == scrim &&
      other.online == online &&
      other.error == error &&
      other.backgroundGradient == backgroundGradient &&
      other.glassBlur == glassBlur &&
      other.titleFontFamily == titleFontFamily;

  @override
  int get hashCode => Object.hash(
        background,
        surface,
        accent,
        textPrimary,
        textDim,
        border,
        myBubble,
        peerBubble,
        scrim,
        online,
        error,
        backgroundGradient,
        glassBlur,
        titleFontFamily,
      );
}

/// The three selectable presets. The enum name (`cozy`/`noir`/`aurora`) is the
/// persisted key; [label] is the user-facing name; [colors] is the palette.
enum MeowThemeId {
  cozy('Cozy', MeowColors.cozy),
  noir('Cinema Noir', MeowColors.noir),
  aurora('Glass Aurora', MeowColors.aurora);

  const MeowThemeId(this.label, this.colors);

  final String label;
  final MeowColors colors;

  static MeowThemeId fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => cozy);
}
