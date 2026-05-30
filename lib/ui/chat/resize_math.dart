import 'dart:ui' show Size, Offset;

/// Smallest usable card size, in logical px.
const double kMinCardWidth = 240;
const double kMinCardHeight = 220;

/// Largest card size, as a fraction of the window.
const double kMaxCardWidthFrac = 0.70;
const double kMaxCardHeightFrac = 0.85;

/// New card size from a bottom-right grip drag.
///
/// The card free-floats top-left-pinned during the drag, so a positive delta
/// always grows the card right/down regardless of which corner it docks to.
/// Result is clamped to [kMinCardWidth]/[kMinCardHeight] and to
/// [kMaxCardWidthFrac]/[kMaxCardHeightFrac] of [windowSize].
Size computeResize({
  required Size startSize,
  required Offset dragDelta,
  required Size windowSize,
}) {
  final maxW = windowSize.width * kMaxCardWidthFrac;
  final maxH = windowSize.height * kMaxCardHeightFrac;
  final w = (startSize.width + dragDelta.dx).clamp(kMinCardWidth, maxW);
  final h = (startSize.height + dragDelta.dy).clamp(kMinCardHeight, maxH);
  return Size(w, h);
}
