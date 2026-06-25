import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/launch/launch_tips.dart';

void main() {
  test('the first tip is the skip hint', () {
    expect(kLaunchTips, isNotEmpty);
    expect(kLaunchTips.first.toLowerCase(), contains('skip'));
  });

  test('launchTip wraps the index around the list', () {
    expect(launchTip(0), kLaunchTips.first);
    expect(launchTip(kLaunchTips.length), kLaunchTips.first);
    expect(launchTip(-1), kLaunchTips.last); // Dart % is non-negative here
  });

  test('the pool offers several distinct one-line nudges', () {
    // More than the original handful, so successive launches actually vary.
    expect(kLaunchTips.length, greaterThan(4));
    // No duplicates — a repeat would waste a rotation slot.
    expect(kLaunchTips.toSet().length, kLaunchTips.length);
    for (final tip in kLaunchTips) {
      expect(tip.trim(), isNotEmpty);
      expect(tip.length, lessThan(70)); // stays on a single low-emphasis row
    }
  });
}
