import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/spacing.dart';

void main() {
  test('spacing exposes the 8-step scale', () {
    expect(
      [Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl],
      [2, 4, 8, 12, 16, 20, 24, 32],
    );
  });

  test('spacing scale strictly ascends (no duplicates)', () {
    const steps = [Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl];
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]), reason: 'step $i must exceed step ${i - 1}');
    }
  });
}
