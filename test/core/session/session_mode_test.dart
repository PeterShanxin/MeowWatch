import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/session/session_mode.dart';

void main() {
  group('resolveSessionMode', () {
    test('toggle off always starts a synced session', () {
      for (final launch in SessionLaunch.values) {
        expect(
          resolveSessionMode(localPlayerMode: false, launch: launch),
          SessionMode.synced,
          reason: launch.name,
        );
      }
    });

    test('toggle on: Start and Continue Watching are local', () {
      expect(
        resolveSessionMode(localPlayerMode: true, launch: SessionLaunch.start),
        SessionMode.local,
      );
      expect(
        resolveSessionMode(
          localPlayerMode: true,
          launch: SessionLaunch.continueWatching,
        ),
        SessionMode.local,
      );
    });

    test('toggle on: join-code and saved-room stay synced', () {
      expect(
        resolveSessionMode(
          localPlayerMode: true,
          launch: SessionLaunch.joinCode,
        ),
        SessionMode.synced,
      );
      expect(
        resolveSessionMode(
          localPlayerMode: true,
          launch: SessionLaunch.savedRoom,
        ),
        SessionMode.synced,
      );
    });
  });

  group('SessionChrome', () {
    test('synced mounts every multiplayer overlay', () {
      final chrome = SessionChrome.forMode(SessionMode.synced);
      expect(chrome.chat, isTrue);
      expect(chrome.reactions, isTrue);
      expect(chrome.reactionBar, isTrue);
      expect(chrome.syncBanners, isTrue);
      expect(chrome.chatTabHint, isTrue);
      expect(chrome.roomShare, isTrue);
      expect(chrome.roster, isTrue);
      expect(chrome.peerLoadPrompt, isTrue);
    });

    test('local mounts none of the multiplayer overlays', () {
      final chrome = SessionChrome.forMode(SessionMode.local);
      expect(chrome.chat, isFalse);
      expect(chrome.reactions, isFalse);
      expect(chrome.reactionBar, isFalse);
      expect(chrome.syncBanners, isFalse);
      expect(chrome.chatTabHint, isFalse);
      expect(chrome.roomShare, isFalse);
      expect(chrome.roster, isFalse);
      expect(chrome.peerLoadPrompt, isFalse);
    });
  });

  test('localPlayerModeFromSetting treats only true as on', () {
    expect(localPlayerModeFromSetting(null), isFalse);
    expect(localPlayerModeFromSetting('false'), isFalse);
    expect(localPlayerModeFromSetting('yes'), isFalse);
    expect(localPlayerModeFromSetting('true'), isTrue);
  });
}
