import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/radii.dart';

void main() {
  test('radii exposes the 6-step ladder', () {
    expect(
      [Radii.xs, Radii.sm, Radii.md, Radii.lg, Radii.xl, Radii.pill],
      [4, 8, 12, 16, 20, 24],
    );
  });

  test('radius ladder strictly ascends', () {
    const steps = [Radii.xs, Radii.sm, Radii.md, Radii.lg, Radii.xl, Radii.pill];
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]));
    }
  });
}
