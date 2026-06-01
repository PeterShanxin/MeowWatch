import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/idle_visibility.dart';

void main() {
  group('chatOverlayOpacity', () {
    test('fully visible when not idle, regardless of other flags', () {
      for (final collapsed in [true, false]) {
        for (final autoDim in [true, false]) {
          expect(
            chatOverlayOpacity(
              idle: false,
              collapsed: collapsed,
              autoDim: autoDim,
            ),
            1.0,
            reason: 'collapsed=$collapsed autoDim=$autoDim',
          );
        }
      }
    });

    test('collapsed tab hides completely when idle (issue #5)', () {
      expect(
        chatOverlayOpacity(idle: true, collapsed: true, autoDim: true),
        0.0,
      );
      // auto-dim setting is irrelevant once collapsed.
      expect(
        chatOverlayOpacity(idle: true, collapsed: true, autoDim: false),
        0.0,
      );
    });

    test('expanded card dims to a ghost when idle and auto-dim on (issue #18)',
        () {
      expect(
        chatOverlayOpacity(idle: true, collapsed: false, autoDim: true),
        0.1,
      );
    });

    test('expanded card stays fully visible when idle and auto-dim off', () {
      expect(
        chatOverlayOpacity(idle: true, collapsed: false, autoDim: false),
        1.0,
      );
    });

    test('expanded card stays a ghost on first idle, before deep idle (#34)',
        () {
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: false,
          autoDim: true,
          deepIdle: false,
        ),
        0.1,
      );
    });

    test('expanded card hides fully after extended (deep) idle (#34)', () {
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: false,
          autoDim: true,
          deepIdle: true,
        ),
        0.0,
      );
    });

    test('collapsed tab stays fully hidden in deep idle too (#34)', () {
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: true,
          autoDim: true,
          deepIdle: true,
        ),
        0.0,
      );
    });

    test('deep idle still respects auto-dim off (chat stays visible)', () {
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: false,
          autoDim: false,
          deepIdle: true,
        ),
        1.0,
      );
    });

    test('collapsed tab with unread stays fully visible when idle (#43)', () {
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: true,
          autoDim: true,
          hasUnread: true,
        ),
        1.0,
      );
    });

    test('collapsed unread tab survives deep idle too (#43)', () {
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: true,
          autoDim: true,
          deepIdle: true,
          hasUnread: true,
        ),
        1.0,
      );
    });

    test('expanded unread card ghosts when wake-on-message off (#43)', () {
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: false,
          autoDim: true,
          hasUnread: true,
          wakeToFullyVisible: false,
        ),
        0.1,
      );
    });

    test('expanded unread card fully wakes when setting on (#43)', () {
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: false,
          autoDim: true,
          hasUnread: true,
          wakeToFullyVisible: true,
        ),
        1.0,
      );
    });

    test('unread expanded card does not hide in deep idle (#43)', () {
      // Without unread this would be 0.0 (#34); unread keeps it a ghost.
      expect(
        chatOverlayOpacity(
          idle: true,
          collapsed: false,
          autoDim: true,
          deepIdle: true,
          hasUnread: true,
          wakeToFullyVisible: false,
        ),
        0.1,
      );
    });
  });

  group('overlayOpacity', () {
    test('fades out when idle', () {
      expect(overlayOpacity(idle: true), 0.0);
    });

    test('visible when not idle', () {
      expect(overlayOpacity(idle: false), 1.0);
    });
  });
}
