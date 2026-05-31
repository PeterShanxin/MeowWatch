import 'dart:ui' show Size, Offset;

import 'chat_corner.dart';

/// Smallest usable card size, in logical px.
const double kMinCardWidth = 240;
const double kMinCardHeight = 160;

/// Largest card size, as a fraction of the window.
const double kMaxCardWidthFrac = 0.70;
const double kMaxCardHeightFrac = 0.85;

/// Default card size, in logical px, used until the user resizes. Persisted
/// sizes are stored in px too, so the card keeps a stable physical size when
/// the window is maximized/resized (most floating overlays behave this way).
const double kDefaultCardWidth = 360;
const double kDefaultCardHeight = 420;

/// Clamp a desired px card size to fit [window]: at least the min, at most the
/// max fraction of the window. If the window is so small the max would fall
/// below the min, the min wins (the card may then exceed a tiny window, but it
/// stays usable). Display-only — never mutates the stored size.
Size clampCardSize(Size desired, Size window) {
  final maxW = window.width * kMaxCardWidthFrac;
  final maxH = window.height * kMaxCardHeightFrac;
  final w = desired.width
      .clamp(kMinCardWidth, maxW < kMinCardWidth ? kMinCardWidth : maxW);
  final h = desired.height
      .clamp(kMinCardHeight, maxH < kMinCardHeight ? kMinCardHeight : maxH);
  return Size(w, h);
}

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
  // Guard against a tiny window where the max would fall below the min, which
  // would make `.clamp(min, max)` throw (it requires min <= max). The min wins.
  final rawMaxW = windowSize.width * kMaxCardWidthFrac;
  final rawMaxH = windowSize.height * kMaxCardHeightFrac;
  final maxW = rawMaxW < kMinCardWidth ? kMinCardWidth : rawMaxW;
  final maxH = rawMaxH < kMinCardHeight ? kMinCardHeight : rawMaxH;

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
