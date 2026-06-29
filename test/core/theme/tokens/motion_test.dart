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
    expect(Motion.reveal, const Duration(milliseconds: 2800));
    expect(Motion.slow < Motion.reveal, isTrue);
  });

  test('the hero/character easings are the agreed cubics', () {
    expect(Motion.emphasized, Curves.easeInOutCubicEmphasized);
    expect(Motion.emphasizedAccelerate, const Cubic(0.3, 0.0, 0.8, 0.15));
    expect(Motion.springy, const Cubic(0.34, 1.26, 0.64, 1.0));
  });

  test('xfast is the press/hover feedback duration, shorter than fast', () {
    expect(Motion.xfast, const Duration(milliseconds: 80));
    expect(Motion.xfast < Motion.fast, isTrue);
  });

  test('elasticPop overshoots harder than springy (the one squash-&-stretch)',
      () {
    expect(Motion.elasticPop, const Cubic(0.2, 1.5, 0.4, 1.0));
    final popPeak = _peak(Motion.elasticPop);
    final springyPeak = _peak(Motion.springy);
    // It actually overshoots past 1.0...
    expect(popPeak, greaterThan(1.05));
    // ...and harder than the gentle springy beat.
    expect(popPeak, greaterThan(springyPeak));
  });
}

/// Highest value a curve reaches across its [0,1] sweep — used to compare
/// overshoot strength between two cubics.
double _peak(Curve c) {
  var peak = 0.0;
  for (var i = 0; i <= 100; i++) {
    final v = c.transform(i / 100);
    if (v > peak) peak = v;
  }
  return peak;
}
