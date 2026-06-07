import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/presence_messages.dart';

void main() {
  group('peerDepartureMessage', () {
    test('clean leave', () {
      expect(
        peerDepartureMessage(username: 'Alice', clean: true),
        'Alice left the room.',
      );
    });

    test('lost connection', () {
      expect(
        peerDepartureMessage(username: 'Bob', clean: false),
        'Bob lost connection.',
      );
    });
  });

  group('peerJoinMessage', () {
    test('first join', () {
      expect(
        peerJoinMessage(username: 'Alice', reconnected: false),
        'Alice joined the room.',
      );
    });

    test('reconnect', () {
      expect(
        peerJoinMessage(username: 'Bob', reconnected: true),
        'Bob reconnected.',
      );
    });
  });

  group('localConnectionLine', () {
    test('first connect: connecting → connected returns null', () {
      expect(
        localConnectionLine(
          prev: SyncConnectionStatus.connecting,
          next: SyncConnectionStatus.connected,
        ),
        isNull,
      );
    });

    test('first connect: handshaking → connected returns null', () {
      expect(
        localConnectionLine(
          prev: SyncConnectionStatus.handshaking,
          next: SyncConnectionStatus.connected,
        ),
        isNull,
      );
    });

    test('reconnect: reconnecting → connected returns Reconnected line', () {
      expect(
        localConnectionLine(
          prev: SyncConnectionStatus.reconnecting,
          next: SyncConnectionStatus.connected,
        ),
        'Reconnected to room.',
      );
    });

    test('drop: connected → reconnecting returns Connection lost line', () {
      expect(
        localConnectionLine(
          prev: SyncConnectionStatus.connected,
          next: SyncConnectionStatus.reconnecting,
        ),
        'Connection lost — reconnecting…',
      );
    });

    test('unrelated transition returns null', () {
      expect(
        localConnectionLine(
          prev: SyncConnectionStatus.disconnected,
          next: SyncConnectionStatus.connecting,
        ),
        isNull,
      );
    });

    test('error transition returns null', () {
      expect(
        localConnectionLine(
          prev: SyncConnectionStatus.connected,
          next: SyncConnectionStatus.error,
        ),
        isNull,
      );
    });
  });

  group('isPeerReconnect', () {
    final now = DateTime(2026, 6, 7, 12, 0, 0);

    test('null departedAt → false', () {
      expect(isPeerReconnect(departedAt: null, now: now), isFalse);
    });

    test('departed just now → true', () {
      final recent = now.subtract(const Duration(seconds: 10));
      expect(isPeerReconnect(departedAt: recent, now: now), isTrue);
    });

    test('departed exactly at window boundary → true', () {
      final atBoundary = now.subtract(const Duration(seconds: 60));
      expect(isPeerReconnect(departedAt: atBoundary, now: now), isTrue);
    });

    test('departed just past window → false', () {
      final tooOld = now.subtract(const Duration(seconds: 61));
      expect(isPeerReconnect(departedAt: tooOld, now: now), isFalse);
    });

    test('custom window respected', () {
      final recent = now.subtract(const Duration(seconds: 30));
      expect(
        isPeerReconnect(
          departedAt: recent,
          now: now,
          window: const Duration(seconds: 20),
        ),
        isFalse,
      );
      expect(
        isPeerReconnect(
          departedAt: recent,
          now: now,
          window: const Duration(seconds: 45),
        ),
        isTrue,
      );
    });
  });
}
