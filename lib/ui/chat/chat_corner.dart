import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Which corner the chat card is anchored to.
enum ChatCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Outcome of dropping the card after a drag: either snap to a corner, or
/// collapse into the right-edge peek dock.
@immutable
class SnapResult {
  const SnapResult.corner(ChatCorner this.corner) : collapsed = false;
  const SnapResult.collapse()
      : corner = null,
        collapsed = true;

  final ChatCorner? corner;
  final bool collapsed;

  @override
  bool operator ==(Object other) =>
      other is SnapResult &&
      other.corner == corner &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(corner, collapsed);
}

/// Decide where the card lands when released at [dropTopLeft].
///
/// Rule: if the card's right edge reaches into the [edgeDockZone] strip along
/// the window's right edge, it collapses. Otherwise it snaps to whichever
/// corner the card's center is nearest (left/right by x, top/bottom by y).
SnapResult computeSnap({
  required Offset dropTopLeft,
  required Size cardSize,
  required Size windowSize,
  double edgeDockZone = 48,
}) {
  final cardRight = dropTopLeft.dx + cardSize.width;
  if (windowSize.width - cardRight <= edgeDockZone) {
    return const SnapResult.collapse();
  }
  final centerX = dropTopLeft.dx + cardSize.width / 2;
  final centerY = dropTopLeft.dy + cardSize.height / 2;
  final left = centerX < windowSize.width / 2;
  final top = centerY < windowSize.height / 2;
  if (top) {
    return SnapResult.corner(left ? ChatCorner.topLeft : ChatCorner.topRight);
  }
  return SnapResult.corner(
      left ? ChatCorner.bottomLeft : ChatCorner.bottomRight);
}
