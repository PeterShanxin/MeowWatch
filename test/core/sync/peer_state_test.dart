import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';

void main() {
  group('PeerPlayState', () {
    test('positionFromSeconds converts float seconds to Duration', () {
      final s = PeerPlayState.fromSeconds(
        seconds: 12.5,
        paused: false,
        doSeek: true,
        setBy: 'lin',
      );
      expect(s.position, const Duration(milliseconds: 12500));
      expect(s.paused, isFalse);
      expect(s.doSeek, isTrue);
      expect(s.setBy, 'lin');
    });

    test('positionSeconds converts Duration back to float seconds', () {
      const s = PeerPlayState(
        position: Duration(milliseconds: 3200),
        paused: true,
      );
      expect(s.positionSeconds, 3.2);
      expect(s.doSeek, isFalse);
    });

    test('equal states are equal', () {
      const a = PeerPlayState(position: Duration(seconds: 1), paused: false);
      const b = PeerPlayState(position: Duration(seconds: 1), paused: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SyncConnectionState', () {
    test('carries status and optional message', () {
      const c = SyncConnectionState(
        status: SyncConnectionStatus.error,
        message: 'boom',
      );
      expect(c.status, SyncConnectionStatus.error);
      expect(c.message, 'boom');
    });
  });

  group('PresenceEvent', () {
    test('captures username and kind', () {
      const e = PresenceEvent(username: 'lin', kind: PresenceKind.joined);
      expect(e.username, 'lin');
      expect(e.kind, PresenceKind.joined);
    });
  });

  group('ChatMessage', () {
    test('captures username and text', () {
      const m = ChatMessage(username: 'lin', text: 'hi');
      expect(m.username, 'lin');
      expect(m.text, 'hi');
    });
  });
}
