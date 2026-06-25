import 'package:flutter/widgets.dart';

import 'meow_logo_mark.dart';
import 'meow_wordmark.dart';

/// The MeowWatch lockup: the [MeowLogoMark] beside (or above) the
/// [MeowWordmark]. Both tint to the live theme. Use [axis] for horizontal
/// (default) or stacked. Set [markLeading] false to put the mark *after* the
/// wordmark — handy when the wordmark must share a left edge with text below it.
class MeowLogo extends StatelessWidget {
  const MeowLogo({
    super.key,
    this.markSize = 40,
    this.fontSize = 24,
    this.axis = Axis.horizontal,
    this.gap = 16,
    this.markLeading = true,
  });

  final double markSize;
  final double fontSize;
  final Axis axis;
  final double gap;
  final bool markLeading;

  @override
  Widget build(BuildContext context) {
    final mark = MeowLogoMark(size: markSize);
    final word = MeowWordmark(fontSize: fontSize);
    final spacer = SizedBox.square(dimension: gap);
    final children = markLeading ? [mark, spacer, word] : [word, spacer, mark];
    return axis == Axis.horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: children)
        : Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
