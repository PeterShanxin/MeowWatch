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

  test('reveal is the launch-only duration, the longest token', () {
    expect(Motion.reveal, const Duration(milliseconds: 1200));
    expect(Motion.slow < Motion.reveal, isTrue);
  });

  test('the hero/character easings are the agreed cubics', () {
    expect(Motion.emphasized, Curves.easeInOutCubicEmphasized);
    expect(Motion.emphasizedAccelerate, const Cubic(0.3, 0.0, 0.8, 0.15));
    expect(Motion.springy, const Cubic(0.34, 1.26, 0.64, 1.0));
  });
}
