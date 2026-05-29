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
/// Rule: collapse to the peek tab only when the card is tucked against the
/// right edge AND dropped near the vertical middle (where the peek tab
/// lives). A drop aimed at a right corner snaps to that corner instead — the
/// edge-collapse strip used to swallow the top/bottom-right corners. Anywhere
/// else snaps to whichever corner the card's center is nearest.
SnapResult computeSnap({
  required Offset dropTopLeft,
  required Size cardSize,
  required Size windowSize,
  double edgeDockZone = 48,
}) {
  final cardRight = dropTopLeft.dx + cardSize.width;
  final centerX = dropTopLeft.dx + cardSize.width / 2;
  final centerY = dropTopLeft.dy + cardSize.height / 2;

  final againstRightEdge = windowSize.width - cardRight <= edgeDockZone;
  final nearVerticalMiddle = centerY > windowSize.height * 0.33 &&
      centerY < windowSize.height * 0.67;
  if (againstRightEdge && nearVerticalMiddle) {
    return const SnapResult.collapse();
  }

  final left = centerX < windowSize.width / 2;
  final top = centerY < windowSize.height / 2;
  if (top) {
    return SnapResult.corner(left ? ChatCorner.topLeft : ChatCorner.topRight);
  }
  return SnapResult.corner(
      left ? ChatCorner.bottomLeft : ChatCorner.bottomRight);
}
