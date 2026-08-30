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

  group('shouldShowLocalJoinOverride', () {
    test('Local default + valid join-code shows the notice', () {
      expect(
        shouldShowLocalJoinOverride(
          persistedLocal: true,
          launch: SessionLaunch.joinCode,
        ),
        isTrue,
      );
      expect(
        shouldShowLocalJoinOverride(
          persistedLocal: true,
          launch: SessionLaunch.savedRoom,
        ),
        isTrue,
      );
    });

    test('invalid destination never shows the notice', () {
      expect(
        shouldShowLocalJoinOverride(
          persistedLocal: true,
          launch: SessionLaunch.joinCode,
          validDestination: false,
        ),
        isFalse,
      );
    });

    test('Local off or Start / Continue never shows the notice', () {
      expect(
        shouldShowLocalJoinOverride(
          persistedLocal: false,
          launch: SessionLaunch.joinCode,
        ),
        isFalse,
      );
      expect(
        shouldShowLocalJoinOverride(
          persistedLocal: true,
          launch: SessionLaunch.start,
        ),
        isFalse,
      );
      expect(
        shouldShowLocalJoinOverride(
          persistedLocal: true,
          launch: SessionLaunch.continueWatching,
        ),
        isFalse,
      );
    });
  });

  test('localPlayerModeFromSetting treats only true as on', () {
    expect(localPlayerModeFromSetting(null), isFalse);
    expect(localPlayerModeFromSetting('false'), isFalse);
    expect(localPlayerModeFromSetting('yes'), isFalse);
    expect(localPlayerModeFromSetting('true'), isTrue);
  });

  group('selectSessionBanner', () {
    const waiting = 'Waiting for a friend to join…';
    const connecting = 'Connecting to room cozy-fox-42…';
    const loadFailure = "Couldn't play that — the page has no video.";
    const resolving = 'Finding the video…';

    test('local keeps a media/load failure notice', () {
      final chrome = SessionChrome.forMode(SessionMode.local);
      expect(
        selectSessionBanner(
          leavingRoom: false,
          notice: loadFailure,
          derivedSync: waiting,
          syncBanners: chrome.syncBanners,
        ),
        loadFailure,
      );
    });

    test('local suppresses waiting and connecting sync hints', () {
      final chrome = SessionChrome.forMode(SessionMode.local);
      expect(
        selectSessionBanner(
          leavingRoom: false,
          derivedSync: waiting,
          syncBanners: chrome.syncBanners,
        ),
        isNull,
      );
      expect(
        selectSessionBanner(
          leavingRoom: false,
          derivedSync: connecting,
          syncBanners: chrome.syncBanners,
        ),
        isNull,
      );
    });

    test('local still shows an in-flight resolve notice', () {
      final chrome = SessionChrome.forMode(SessionMode.local);
      expect(
        selectSessionBanner(
          leavingRoom: false,
          resolving: resolving,
          notice: loadFailure,
          derivedSync: waiting,
          syncBanners: chrome.syncBanners,
        ),
        resolving,
      );
    });

    test('synced still shows derived waiting when nothing else is up', () {
      final chrome = SessionChrome.forMode(SessionMode.synced);
      expect(
        selectSessionBanner(
          leavingRoom: false,
          derivedSync: waiting,
          syncBanners: chrome.syncBanners,
        ),
        waiting,
      );
    });

    test('leaving the room silences every notice', () {
      final chrome = SessionChrome.forMode(SessionMode.synced);
      expect(
        selectSessionBanner(
          leavingRoom: true,
          resolving: resolving,
          notice: loadFailure,
          derivedSync: waiting,
          syncBanners: chrome.syncBanners,
        ),
        isNull,
      );
    });
  });
}
