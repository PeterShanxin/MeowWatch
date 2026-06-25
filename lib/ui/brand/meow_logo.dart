import 'package:flutter/widgets.dart';

import 'meow_logo_mark.dart';
import 'meow_wordmark.dart';

/// The MeowWatch lockup: the [MeowLogoMark] beside (or above) the
/// [MeowWordmark]. Both tint to the live theme. Use [axis] for horizontal
/// (default) or stacked.
class MeowLogo extends StatelessWidget {
  const MeowLogo({
    super.key,
    this.markSize = 40,
    this.fontSize = 24,
    this.axis = Axis.horizontal,
    this.gap = 16,
  });

  final double markSize;
  final double fontSize;
  final Axis axis;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final mark = MeowLogoMark(size: markSize);
    final word = MeowWordmark(fontSize: fontSize);
    final children = [mark, SizedBox.square(dimension: gap), word];
    return axis == Axis.horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: children)
        : Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
