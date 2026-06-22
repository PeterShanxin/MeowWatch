import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/motion.dart';

void main() {
  test('durations ascend fast < base < slow', () {
    expect(Motion.fast, const Duration(milliseconds: 120));
    expect(Motion.base, const Duration(milliseconds: 200));
    expect(Motion.slow, const Duration(milliseconds: 320));
    expect(Motion.fast < Motion.base, isTrue);
    expect(Motion.base < Motion.slow, isTrue);
  });

  test('curves are the two standard easings', () {
    expect(Motion.standard, Curves.easeOutCubic);
    expect(Motion.symmetric, Curves.easeInOut);
  });

  test('stagger is the per-item cascade delay, shorter than fast', () {
    expect(Motion.stagger, const Duration(milliseconds: 55));
    expect(Motion.stagger < Motion.fast, isTrue);
  });
}
