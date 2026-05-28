import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';

void main() {
  const window = Size(1000, 800);
  const card = Size(300, 200);

  SnapResult snap(Offset topLeft) => computeSnap(
        dropTopLeft: topLeft,
        cardSize: card,
        windowSize: window,
      );

  test('top-left region snaps to topLeft', () {
    final r = snap(const Offset(20, 20));
    expect(r.collapsed, isFalse);
    expect(r.corner, ChatCorner.topLeft);
  });

  test('bottom-left region snaps to bottomLeft', () {
    final r = snap(const Offset(20, 560));
    expect(r.corner, ChatCorner.bottomLeft);
  });

  test('top-left of a left-leaning card mid-screen still picks by center', () {
    expect(snap(const Offset(20, 20)).corner, ChatCorner.topLeft);
  });

  test('right-edge drop collapses into the dock', () {
    final r = snap(const Offset(690, 300));
    expect(r.collapsed, isTrue);
    expect(r.corner, isNull);
  });

  test('a left-side drop never collapses', () {
    expect(snap(const Offset(20, 300)).collapsed, isFalse);
  });
}
