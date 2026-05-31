import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/ui/sync_activity_text.dart';

void main() {
  SyncActivityText text(SyncActivityKind kind, Duration pos) =>
      syncActivityText(SyncActivity(
        kind: kind,
        username: 'lin',
        position: pos,
      ));

  test('paused includes position with emoji in banner, plain in chat', () {
    final t = text(SyncActivityKind.paused, const Duration(seconds: 750));
    expect(t.banner, '⏸ lin paused at 12:30');
    expect(t.chatLine, 'lin paused at 12:30');
  });

  test('played omits position', () {
    final t = text(SyncActivityKind.played, const Duration(seconds: 750));
    expect(t.banner, '▶ lin resumed');
    expect(t.chatLine, 'lin resumed');
  });

  test('forward seek wording', () {
    final t = text(SyncActivityKind.seekedForward, const Duration(seconds: 2700));
    expect(t.banner, '⏩ lin skipped to 45:00');
    expect(t.chatLine, 'lin skipped to 45:00');
  });

  test('backward seek wording', () {
    final t = text(SyncActivityKind.seekedBack, const Duration(seconds: 600));
    expect(t.banner, '⏪ lin jumped back to 10:00');
    expect(t.chatLine, 'lin jumped back to 10:00');
  });

  test('over an hour uses h:mm:ss', () {
    final t = text(SyncActivityKind.paused, const Duration(seconds: 3725));
    expect(t.chatLine, 'lin paused at 1:02:05');
  });
}
