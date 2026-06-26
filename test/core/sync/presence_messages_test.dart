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

  group('isConnectionDrop', () {
    test('connected → reconnecting is a drop', () {
      expect(
        isConnectionDrop(
          prev: SyncConnectionStatus.connected,
          next: SyncConnectionStatus.reconnecting,
        ),
        isTrue,
      );
    });

    test('repeated backoff (handshaking → reconnecting) is not a drop', () {
      // Avoids re-announcing "connection lost" on every retry attempt.
      expect(
        isConnectionDrop(
          prev: SyncConnectionStatus.handshaking,
          next: SyncConnectionStatus.reconnecting,
        ),
        isFalse,
      );
    });

    test('connected → connected is not a drop', () {
      expect(
        isConnectionDrop(
          prev: SyncConnectionStatus.connected,
          next: SyncConnectionStatus.connected,
        ),
        isFalse,
      );
    });
  });

  group('isReconnectSuccess', () {
    test('latched + arriving at connected is a success', () {
      expect(
        isReconnectSuccess(
          wasReconnecting: true,
          next: SyncConnectionStatus.connected,
        ),
        isTrue,
      );
    });

    test('fires across the intermediate handshaking state', () {
      // The reconnect path is connected → reconnecting → handshaking →
      // connected. The latch (set on the drop) must survive handshaking so the
      // success still fires when connected finally arrives.
      var wasReconnecting = false;
      // Drop:
      if (isConnectionDrop(
        prev: SyncConnectionStatus.connected,
        next: SyncConnectionStatus.reconnecting,
      )) {
        wasReconnecting = true;
      }
      // Intermediate handshaking — not connected, no success yet:
      expect(
        isReconnectSuccess(
          wasReconnecting: wasReconnecting,
          next: SyncConnectionStatus.handshaking,
        ),
        isFalse,
      );
      // Connected — success now fires:
      expect(
        isReconnectSuccess(
          wasReconnecting: wasReconnecting,
          next: SyncConnectionStatus.connected,
        ),
        isTrue,
      );
    });

    test('first connect (no latch) is not a reconnect success', () {
      expect(
        isReconnectSuccess(
          wasReconnecting: false,
          next: SyncConnectionStatus.connected,
        ),
        isFalse,
      );
    });

    test('latched but not yet connected is not a success', () {
      expect(
        isReconnectSuccess(
          wasReconnecting: true,
          next: SyncConnectionStatus.reconnecting,
        ),
        isFalse,
      );
    });
  });

  group('ownGhostNameOnReconnect', () {
    test('reconnect with a server suffix → our chosen name is the ghost', () {
      // We asked for "meowPEOW"; the server handed back "meowPEOW_" because our
      // own dropped session still held the clean name. That lingering ghost is
      // about to be reaped — its departure must not read as a peer drop.
      expect(
        ownGhostNameOnReconnect(
          reconnected: true,
          chosenName: 'meowPEOW',
          assignedName: 'meowPEOW_',
        ),
        'meowPEOW',
      );
    });

    test('reconnect with no suffix (name was free) → no ghost', () {
      expect(
        ownGhostNameOnReconnect(
          reconnected: true,
          chosenName: 'meowPEOW',
          assignedName: 'meowPEOW',
        ),
        isNull,
      );
    });

    test('reconnect with no assigned name → no ghost', () {
      expect(
        ownGhostNameOnReconnect(
          reconnected: true,
          chosenName: 'meowPEOW',
          assignedName: null,
        ),
        isNull,
      );
    });

    test('first connect with a suffix is a real namesake, not our ghost', () {
      // No prior session of ours exists on a first connect, so a suffix means a
      // genuinely different user already holds the name. Forwarding their
      // departure is correct (#93) — never suppress it.
      expect(
        ownGhostNameOnReconnect(
          reconnected: false,
          chosenName: 'meowPEOW',
          assignedName: 'meowPEOW_',
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
