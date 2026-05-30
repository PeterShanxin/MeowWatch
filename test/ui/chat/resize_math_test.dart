import 'package:flutter/widgets.dart' show Size, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/resize_math.dart';

void main() {
  const window = Size(1000, 800); // maxW=700, maxH=680
  const start = Size(300, 400);

  test('grows width and height with positive delta', () {
    final r = computeResize(
      startSize: start,
      dragDelta: const Offset(50, 30),
      windowSize: window,
    );
    expect(r.width, 350);
    expect(r.height, 430);
  });

  test('shrinks with negative delta', () {
    final r = computeResize(
      startSize: start,
      dragDelta: const Offset(-40, -20),
      windowSize: window,
    );
    expect(r.width, 260);
    expect(r.height, 380);
  });

  test('clamps to minimum size', () {
    final r = computeResize(
      startSize: start,
      dragDelta: const Offset(-500, -500),
      windowSize: window,
    );
    expect(r.width, kMinCardWidth);
    expect(r.height, kMinCardHeight);
  });

  test('clamps to maximum fraction of window', () {
    final r = computeResize(
      startSize: start,
      dragDelta: const Offset(9999, 9999),
      windowSize: window,
    );
    expect(r.width, window.width * kMaxCardWidthFrac); // 700
    expect(r.height, window.height * kMaxCardHeightFrac); // 680
  });
}
