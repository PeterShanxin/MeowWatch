import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/idle_rearm_throttle.dart';

/// Pure logic for throttling how often a high-frequency interaction event
/// (pointer hover/move, hundreds/sec) re-arms the UI idle timer. Re-arming
/// means cancel + allocate a Timer; doing it every event is wasted churn when
/// the idle delay is measured in seconds.
void main() {
  Duration ms(int v) => Duration(milliseconds: v);

  test('first event always re-arms', () {
    final t = IdleRearmThrottle(minInterval: ms(200));
    expect(t.shouldRearm(ms(0)), isTrue);
  });

  test('a second event within the window does not re-arm', () {
    final t = IdleRearmThrottle(minInterval: ms(200));
    t.shouldRearm(ms(0));
    expect(t.shouldRearm(ms(50)), isFalse);
    expect(t.shouldRearm(ms(199)), isFalse);
  });

  test('an event at or past the window re-arms', () {
    final t = IdleRearmThrottle(minInterval: ms(200));
    t.shouldRearm(ms(0));
    expect(t.shouldRearm(ms(200)), isTrue);
  });

  test('the window is measured from the last re-arm, not the last event', () {
    final t = IdleRearmThrottle(minInterval: ms(200));
    expect(t.shouldRearm(ms(0)), isTrue); // baseline 0
    expect(t.shouldRearm(ms(150)), isFalse); // within, no baseline move
    expect(t.shouldRearm(ms(200)), isTrue); // 200 - 0 >= 200 -> baseline 200
    expect(t.shouldRearm(ms(350)), isFalse); // 350 - 200 < 200
    expect(t.shouldRearm(ms(400)), isTrue); // 400 - 200 >= 200
  });

  test('reset() forces the next event to re-arm immediately', () {
    final t = IdleRearmThrottle(minInterval: ms(200));
    t.shouldRearm(ms(1000));
    // Well within the window, but a wake-from-idle resets the throttle.
    t.reset();
    expect(t.shouldRearm(ms(1010)), isTrue);
  });
}
