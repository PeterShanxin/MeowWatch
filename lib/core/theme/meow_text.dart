import 'package:flutter/material.dart';

import 'meow_context.dart';
import 'meow_theme.dart';
import 'tokens/type_scale.dart';

/// Text styles composed from the global [TypeScale] (size/weight) and the active
/// theme's [MeowColors] (color + titleFontFamily). Access via `context.meowText`.
///
/// Base styles use [MeowColors.textPrimary]; for dim text, call sites apply
/// `.copyWith(color: context.meow.textDim)`. title/heading/display carry the
/// theme's titleFontFamily (serif on Noir); smaller roles do not.
@immutable
class MeowTextStyles {
  const MeowTextStyles(this._c);
  final MeowColors _c;

  TextStyle get caption => TextStyle(
        fontSize: TypeScale.caption,
        fontWeight: TypeScale.regular,
        color: _c.textPrimary,
      );

  TextStyle get body => TextStyle(
        fontSize: TypeScale.body,
        fontWeight: TypeScale.regular,
        color: _c.textPrimary,
      );

  TextStyle get label => TextStyle(
        fontSize: TypeScale.label,
        fontWeight: TypeScale.medium,
        color: _c.textPrimary,
      );

  TextStyle get title => TextStyle(
        fontSize: TypeScale.title,
        fontWeight: TypeScale.semibold,
        color: _c.textPrimary,
        fontFamily: _c.titleFontFamily,
      );

  TextStyle get heading => TextStyle(
        fontSize: TypeScale.heading,
        fontWeight: TypeScale.semibold,
        color: _c.textPrimary,
        fontFamily: _c.titleFontFamily,
      );

  TextStyle get display => TextStyle(
        fontSize: TypeScale.display,
        fontWeight: TypeScale.bold,
        color: _c.textPrimary,
        fontFamily: _c.titleFontFamily,
      );
}

/// `context.meowText.body` — the active theme's composed text styles.
extension MeowTextContext on BuildContext {
  MeowTextStyles get meowText => MeowTextStyles(meow);
}
