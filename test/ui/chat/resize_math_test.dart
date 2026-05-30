import 'package:flutter/widgets.dart' show Size, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/resize_math.dart';

void main() {
  const window = Size(1000, 800); // maxW=700, maxH=680
  const startTL = Offset(100, 100);
  const startSize = Size(300, 400); // anchor rect: L=100,T=100,R=400,B=500

  test('bottom-right grip grows down-right, top-left pinned', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(50, 30),
      grip: ChatCorner.bottomRight,
      windowSize: window,
    );
    expect(r.size, const Size(350, 430));
    expect(r.topLeft, const Offset(100, 100));
  });

  test('top-left grip grows up-left, bottom-right pinned', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(-40, -20),
      grip: ChatCorner.topLeft,
      windowSize: window,
    );
    expect(r.size, const Size(340, 420));
    expect(r.topLeft, const Offset(60, 80));
  });

  test('top-right grip: top moves, left pinned', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(20, -10),
      grip: ChatCorner.topRight,
      windowSize: window,
    );
    expect(r.size, const Size(320, 410));
    expect(r.topLeft, const Offset(100, 90));
  });

  test('bottom-left grip: left moves, top pinned', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(-30, 25),
      grip: ChatCorner.bottomLeft,
      windowSize: window,
    );
    expect(r.size, const Size(330, 425));
    expect(r.topLeft, const Offset(70, 100));
  });

  test('clamps to minimum and keeps the anchored corner fixed', () {
    // topLeft grip dragged toward the anchor (down-right, positive) shrinks the
    // card; a huge drag clamps to the minimum while the bottom-right anchor
    // (400,500) stays put.
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(9999, 9999),
      grip: ChatCorner.topLeft,
      windowSize: window,
    );
    expect(r.size, const Size(kMinCardWidth, kMinCardHeight));
    expect(r.topLeft, Offset(400 - kMinCardWidth, 500 - kMinCardHeight));
  });

  test('clamps to maximum fraction of window', () {
    final r = computeCornerResize(
      startTopLeft: startTL,
      startSize: startSize,
      dragDelta: const Offset(9999, 9999),
      grip: ChatCorner.bottomRight,
      windowSize: window,
    );
    expect(r.size, Size(window.width * kMaxCardWidthFrac, window.height * kMaxCardHeightFrac));
    expect(r.topLeft, const Offset(100, 100));
  });
}
