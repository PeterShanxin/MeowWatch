import 'package:flutter_test/flutter_test.dart';

import 'tolerant_golden_comparator.dart';

void main() {
  test('hosted Windows font drift at the observed CI delta is allowed', () {
    // windows-2025 vs the committed goldens: 0.05% / 444px and ~15px.
    expect(allowHostedWindowsGoldenDrift(0.05), isTrue);
    expect(allowHostedWindowsGoldenDrift(0.00), isTrue);
    expect(allowHostedWindowsGoldenDrift(kHostedWindowsGoldenDriftPercent), isTrue);
  });

  test('a real layout change is still a failure', () {
    expect(allowHostedWindowsGoldenDrift(0.11), isFalse);
    expect(allowHostedWindowsGoldenDrift(1.0), isFalse);
  });
}
