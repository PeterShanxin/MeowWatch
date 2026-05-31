import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_activity_throttle.dart';

void main() {
  SyncActivity activity(SyncActivityKind kind, int seconds) => SyncActivity(
        kind: kind,
        username: 'lin',
        position: Duration(seconds: seconds),
      );

  late SyncActivityThrottle throttle;
  late List<SyncActivity> out;

  setUp(() {
    throttle = SyncActivityThrottle(window: const Duration(milliseconds: 40));
    out = <SyncActivity>[];
    throttle.stream.listen(out.add);
  });

  tearDown(() => throttle.dispose());

  test('pause/play pass straight through (no debounce)', () async {
    throttle.add(activity(SyncActivityKind.paused, 12));
    throttle.add(activity(SyncActivityKind.played, 12));
    await Future<void>.delayed(Duration.zero);
    expect(out.map((a) => a.kind),
        [SyncActivityKind.paused, SyncActivityKind.played]);
  });

  test('a burst of seeks collapses into a single final notification (#26)',
      () async {
    // Simulate scrubbing: many rapid seek events, each within the window.
    for (var s = 1; s <= 5; s++) {
      throttle.add(activity(SyncActivityKind.seekedForward, s * 10));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    // Nothing emitted yet — still inside the debounce window.
    expect(out, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(out, hasLength(1));
    expect(out.single.kind, SyncActivityKind.seekedForward);
    // The LAST seek (landing position) is the one that survives.
    expect(out.single.position, const Duration(seconds: 50));
  });

  test('a lone seek is emitted once the window elapses', () async {
    throttle.add(activity(SyncActivityKind.seekedBack, 30));
    expect(out, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(out, hasLength(1));
    expect(out.single.kind, SyncActivityKind.seekedBack);
  });

  test('a pause arriving mid-scrub flushes the pending seek first', () async {
    throttle.add(activity(SyncActivityKind.seekedForward, 20));
    throttle.add(activity(SyncActivityKind.paused, 20));
    await Future<void>.delayed(Duration.zero);
    // Seek flushed immediately ahead of the pause, preserving order.
    expect(out.map((a) => a.kind),
        [SyncActivityKind.seekedForward, SyncActivityKind.paused]);
  });

  test('no emissions after dispose', () async {
    throttle.add(activity(SyncActivityKind.seekedForward, 10));
    await throttle.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(out, isEmpty);
  });
}
