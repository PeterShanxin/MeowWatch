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
}
