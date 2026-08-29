import 'package:flutter_test/flutter_test.dart';

import 'hosted_windows_golden.dart';

void main() {
  test('hosted-Windows golden cap is 0.1% of pixels, not a skip', () {
    expect(kHostedWindowsGoldenMaxDiffFraction, 0.001);
  });

  test('exact match always passes', () {
    expect(
      hostedWindowsGoldenPassed(exactMatch: true, diffPercent: 0),
      isTrue,
    );
  });

  test('CI-observed 0.05% / 444px on 1280x720 is allowed', () {
    // 444 / (1280 * 720) ≈ 0.000482 → logged as 0.05%
    expect(
      hostedWindowsGoldenPassed(exactMatch: false, diffPercent: 444 / (1280 * 720)),
      isTrue,
    );
  });

  test('CI-observed 15px empty-card miss is allowed', () {
    expect(
      hostedWindowsGoldenPassed(exactMatch: false, diffPercent: 15 / (1280 * 720)),
      isTrue,
    );
  });

  test('a 1% layout/theme change still fails', () {
    expect(
      hostedWindowsGoldenPassed(exactMatch: false, diffPercent: 0.01),
      isFalse,
    );
  });
}
