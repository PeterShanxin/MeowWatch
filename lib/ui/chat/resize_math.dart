import 'dart:ui' show Size, Offset;

import 'chat_corner.dart';

/// Smallest usable card size, in logical px.
const double kMinCardWidth = 240;
const double kMinCardHeight = 160;

/// Largest card size, as a fraction of the window.
const double kMaxCardWidthFrac = 0.70;
const double kMaxCardHeightFrac = 0.85;

/// New top-left + size from dragging one corner [grip] of the card.
///
/// The corner opposite [grip] is the anchor and stays fixed; the dragged corner
/// follows the accumulated [dragDelta]. Width/height are clamped to the min/max
/// bounds, and the position is recomputed from the fixed edge AFTER clamping so
/// the anchored corner never drifts. The card free-floats during the drag, so
/// growth direction is encoded by which corner is grabbed.
({Offset topLeft, Size size}) computeCornerResize({
  required Offset startTopLeft,
  required Size startSize,
  required Offset dragDelta,
  required ChatCorner grip,
  required Size windowSize,
}) {
  final maxW = windowSize.width * kMaxCardWidthFrac;
  final maxH = windowSize.height * kMaxCardHeightFrac;

  final isRight = grip == ChatCorner.topRight || grip == ChatCorner.bottomRight;
  final isBottom =
      grip == ChatCorner.bottomLeft || grip == ChatCorner.bottomRight;

  final double newWidth;
  final double newLeft;
  if (isRight) {
    newWidth = (startSize.width + dragDelta.dx).clamp(kMinCardWidth, maxW);
    newLeft = startTopLeft.dx;
  } else {
    final rightEdge = startTopLeft.dx + startSize.width;
    newWidth = (startSize.width - dragDelta.dx).clamp(kMinCardWidth, maxW);
    newLeft = rightEdge - newWidth;
  }

  final double newHeight;
  final double newTop;
  if (isBottom) {
    newHeight = (startSize.height + dragDelta.dy).clamp(kMinCardHeight, maxH);
    newTop = startTopLeft.dy;
  } else {
    final bottomEdge = startTopLeft.dy + startSize.height;
    newHeight = (startSize.height - dragDelta.dy).clamp(kMinCardHeight, maxH);
    newTop = bottomEdge - newHeight;
  }

  return (topLeft: Offset(newLeft, newTop), size: Size(newWidth, newHeight));
}
