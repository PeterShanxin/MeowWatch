import 'package:flutter/widgets.dart';

import '../../core/theme/meow_context.dart';

/// The "MeowWatch" wordmark in Sora 600: "Meow" in the light text color,
/// "Watch" in the theme accent, with a soft accent glow. Colors default to the
/// live theme.
class MeowWordmark extends StatelessWidget {
  const MeowWordmark({
    super.key,
    this.fontSize = 24,
    this.meowColor,
    this.watchColor,
    this.glowColor,
  });

  final double fontSize;
  final Color? meowColor;
  final Color? watchColor;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final meow = meowColor ?? c.textPrimary;
    final watch = watchColor ?? c.accent;
    final glow = glowColor ?? c.accent;

    final base = TextStyle(
      fontFamily: 'Sora',
      fontWeight: FontWeight.w600,
      fontSize: fontSize,
      letterSpacing: fontSize * 0.01,
      height: 1,
      shadows: [
        Shadow(
          color: glow.withValues(alpha: 0.5),
          blurRadius: fontSize * 0.58,
        ),
      ],
    );

    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Meow', style: base.copyWith(color: meow)),
        TextSpan(text: 'Watch', style: base.copyWith(color: watch)),
      ]),
    );
  }
}
