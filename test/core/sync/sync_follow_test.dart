import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_follow.dart';

void main() {
  group('decideFollow', () {
    test('applies a peer pause flip', () {
      final action = decideFollow(
        global: const PeerPlayState(
            position: Duration(seconds: 5), paused: true, setBy: 'lin'),
        localPaused: false,
        localPosition: const Duration(seconds: 5),
        username: 'me',
      );
      expect(action.shouldApply, isTrue);
      expect(action.paused, isTrue);
      expect(action.position, const Duration(seconds: 5));
    });

    test('ignores our own unpause echoed back', () {
      final action = decideFollow(
        global: const PeerPlayState(
            position: Duration(seconds: 5), paused: false, setBy: 'me'),
        localPaused: false, // we already unpaused locally
        localPosition: const Duration(seconds: 5),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('applies an explicit seek made by the peer', () {
      final action = decideFollow(
        global: const PeerPlayState(
            position: Duration(seconds: 60),
            paused: false,
            doSeek: true,
            setBy: 'lin'),
        localPaused: false,
        localPosition: const Duration(seconds: 5),
        username: 'me',
      );
      expect(action.shouldApply, isTrue);
      expect(action.position, const Duration(seconds: 60));
    });

    test('ignores our own seek echoed back', () {
      final action = decideFollow(
        global: const PeerPlayState(
            position: Duration(seconds: 60),
            paused: false,
            doSeek: true,
            setBy: 'me'),
        localPaused: false,
        localPosition: const Duration(seconds: 60),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('does nothing on a steady heartbeat with small drift', () {
      final action = decideFollow(
        global: const PeerPlayState(
            position: Duration(seconds: 11), paused: false, setBy: 'lin'),
        localPaused: false,
        localPosition: const Duration(seconds: 10),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('rewinds when local player is far ahead of the room', () {
      final action = decideFollow(
        global: const PeerPlayState(
            position: Duration(seconds: 10), paused: false, setBy: 'lin'),
        localPaused: false,
        localPosition: const Duration(seconds: 20), // 10s ahead
        username: 'me',
      );
      expect(action.shouldApply, isTrue);
      expect(action.position, const Duration(seconds: 10));
    });

    test('does not rewind to a setter-less global (empty-room reset to 0)', () {
      // After both clients drop and rejoin, the server's fresh room state is
      // position 0 with no setBy. We are mid-film and "far ahead" of it, but
      // must NOT rewind to that phantom zero — only a real peer position counts.
      final action = decideFollow(
        global: const PeerPlayState(
          position: Duration.zero,
          paused: false,
        ),
        localPaused: false,
        localPosition: const Duration(seconds: 500),
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });

    test('does not rewind when local player is behind the room', () {
      final action = decideFollow(
        global: const PeerPlayState(
            position: Duration(seconds: 20), paused: false, setBy: 'lin'),
        localPaused: false,
        localPosition: const Duration(seconds: 10), // 10s behind
        username: 'me',
      );
      expect(action.shouldApply, isFalse);
    });
  });
}
