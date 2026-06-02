import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/notify_decision.dart';

NotifyKind call({
  bool isSystem = false,
  bool isOwn = false,
  bool focused = false,
  bool collapsed = false,
  bool dimmedByIdle = false,
  bool playing = false,
}) =>
    decideNotify(
      isSystem: isSystem,
      isOwnMessage: isOwn,
      windowFocused: focused,
      chatCollapsed: collapsed,
      chatDimmedByIdle: dimmedByIdle,
      videoPlaying: playing,
    );

void main() {
  test('own message never sounds', () {
    expect(call(isOwn: true, focused: false), NotifyKind.none);
  });

  test('system line never sounds (#57)', () {
    expect(call(isSystem: true, focused: false), NotifyKind.none);
    expect(call(isSystem: true, focused: true, collapsed: true, playing: true),
        NotifyKind.none);
  });

  test('unfocused peer message → primary', () {
    expect(call(focused: false), NotifyKind.primary);
    expect(call(focused: false, collapsed: true, playing: true),
        NotifyKind.primary);
  });

  test('focused + collapsed + playing → secondary', () {
    expect(call(focused: true, collapsed: true, playing: true),
        NotifyKind.secondary);
  });

  test('focused + expanded but dimmed/hidden by idle + playing → secondary', () {
    // The expanded card faded to the idle ghost (or deep-idle invisible) — the
    // user can't read it, so the quiet sound still fires.
    expect(call(focused: true, dimmedByIdle: true, playing: true),
        NotifyKind.secondary);
  });

  test('focused + chat open and readable → none', () {
    expect(call(focused: true, collapsed: false, playing: true),
        NotifyKind.none);
  });

  test('focused + collapsed but paused → none', () {
    expect(call(focused: true, collapsed: true, playing: false),
        NotifyKind.none);
  });

  test('focused + dimmed by idle but paused → none', () {
    expect(call(focused: true, dimmedByIdle: true, playing: false),
        NotifyKind.none);
  });
}
