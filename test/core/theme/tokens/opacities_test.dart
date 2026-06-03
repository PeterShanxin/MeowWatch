import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/opacities.dart';

void main() {
  test('opacity levels have the agreed values', () {
    expect(Opacities.dim, 0.60);
    expect(Opacities.scrim, 0.50);
    expect(Opacities.disabled, 0.38);
    expect(Opacities.pressed, 0.12);
    expect(Opacities.hover, 0.08);
  });

  test('every level is a valid alpha in (0, 1]', () {
    for (final a in [Opacities.dim, Opacities.scrim, Opacities.disabled, Opacities.pressed, Opacities.hover]) {
      expect(a, greaterThan(0));
      expect(a, lessThanOrEqualTo(1));
    }
  });
}
