import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/shadows.dart';

void main() {
  const black = Color(0xFF000000);

  test('card shadow geometry + scrim-derived color', () {
    final s = Shadows.card(black).single;
    expect(s.blurRadius, 16);
    expect(s.offset, const Offset(0, 4));
    expect(s.color.a, closeTo(0.45, 0.01)); // alpha channel as 0..1 double
  });

  test('overlay shadow is heavier than card', () {
    final card = Shadows.card(black).single;
    final overlay = Shadows.overlay(black).single;
    expect(overlay.blurRadius, greaterThan(card.blurRadius));
    expect(overlay.offset.dy, greaterThan(card.offset.dy));
  });
}
