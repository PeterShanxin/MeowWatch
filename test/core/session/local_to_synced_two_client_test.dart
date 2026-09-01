import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/session/session_services.dart';
import 'package:meowwatch/core/video/playback_state.dart';

import '../../support/scripted_video_core.dart';
import '../../support/syncplay_room_server.dart';

/// Two-instance integration coverage for the live Local -> Synced switch (#252).
///
/// These tests stand up the REAL seams — a real `SyncplayClient` over a real
/// loopback socket, a real `PlaybackSyncBridge`, a real [SessionServices] —
/// against a Syncplay-faithful room server ([SyncplayRoomServer]). That is what
/// lets them catch the field regression: the failure was not in any single unit
/// but in the *lifecycle*, where a bridge built after the player was already
/// running never learned its source was open, published nothing to the room, and
/// left the session drivable but unable to drive.
void main() {
  const movie = r'C:\videos\movie.mkv';
  const hostStart = Duration(minutes: 5);

  late SyncplayRoomServer server;
  final open = <SessionServices>[];
  final cores = <ScriptedVideoCore>[];

  /// Every client keeps its real diagnostic sink wired. A throwing/absent logger
  /// once wedged the peer-state drain in the field, so the fakes here exercise
  /// the logging path rather than bypassing it.
  final logs = <String>[];

  setUp(() async {
    logs.clear();
    server = await SyncplayRoomServer.start();
  });

  tearDown(() async {
    for (final session in open) {
      await session.dispose();
    }
    open.clear();
    for (final core in cores) {
      await core.dispose();
    }
    cores.clear();
    await server.close();
  });

  ScriptedVideoCore newCore() {
    final core = ScriptedVideoCore();
    cores.add(core);
    return core;
  }

  SessionServices track(SessionServices session) {
    open.add(session);
    return session;
  }

  /// A peer that entered the room synced from the start, loading its file the
  /// way `HomeScreen._load` does: open the source, then confirm it to the bridge
  /// with `markSourceOpen`.
  Future<SessionServices> joinSynced(
    String name, {
    required ScriptedVideoCore video,
    Duration at = Duration.zero,
    bool playing = false,
  }) async {
    video.openAt(movie, at: at, playing: playing);
    final session = track(
      SessionServices.synced(
        video: video,
        onLog: (l) => logs.add('[$name] $l'),
      ),
    );
    await pumpEventQueue();
    session.bridge!.markSourceOpen(movie);
    await server.dial(session.sync!, name: name);
    return session;
  }

  /// Product Check 6: join the room first (empty player), then load the file.
  /// HomeScreen connects on enter; the user loads afterwards. The server's
  /// first State therefore lands before any source is open.
  Future<SessionServices> joinThenLoad(
    String name, {
    required ScriptedVideoCore video,
  }) async {
    final session = track(
      SessionServices.synced(
        video: video,
        onLog: (l) => logs.add('[$name] $l'),
      ),
    );
    await server.dial(session.sync!, name: name);
    await pumpEventQueue();
    video.openAt(movie);
    await pumpEventQueue();
    session.bridge!.markSourceOpen(movie);
    return session;
  }

  /// A peer that watched locally first and then turned Local Player Mode OFF
  /// inside the player — the repro under test.
  Future<SessionServices> switchLocalToSynced(
    String name, {
    required ScriptedVideoCore video,
    required Duration at,
    bool playing = false,
  }) async {
    final session = track(SessionServices.local());
    video.openAt(movie, at: at, playing: playing);
    await pumpEventQueue();
    expect(session.isLocal, isTrue);
    expect(session.sync, isNull);
    session.startSynced(
      video: video,
      openSource: movie,
      onLog: (l) => logs.add('[$name] $l'),
    );
    await server.dial(session.sync!, name: name);
    return session;
  }

  test('1. a normally synced room controls both ways', () async {
    final hostVideo = newCore();
    final peerVideo = newCore();
    await joinSynced('host', video: hostVideo);
    await joinSynced('peer', video: peerVideo);

    hostVideo.userPlay();
    await _until(() => peerVideo.state.status == PlaybackStatus.playing);
    expect(
      peerVideo.state.status,
      PlaybackStatus.playing,
      reason: 'host -> peer play must propagate',
    );

    await _settleRemote();
    peerVideo.userPause();
    await _until(() => hostVideo.state.status == PlaybackStatus.paused);
    expect(
      hostVideo.state.status,
      PlaybackStatus.paused,
      reason: 'peer -> host pause must propagate',
    );
    expect(logs, isNotEmpty, reason: 'the real log sink must have been used');
  });

  test(
    '2+3. a peer joining after Local -> Synced converges to the host state',
    () async {
      final hostVideo = newCore();
      await switchLocalToSynced('host', video: hostVideo, at: hostStart);
      await _until(() => server.roomSetBy == 'host');

      expect(
        server.roomSetBy,
        'host',
        reason:
            'the switch must establish this session as the room playback state '
            '— otherwise the room stays at 0:00 and a joiner has nothing to '
            'converge to',
      );
      expect(
        server.roomPosition,
        _closeTo(hostStart),
        reason: 'the room must adopt the position the host was already at',
      );

      final peerVideo = newCore();
      await joinSynced('peer', video: peerVideo);
      await _until(() => _near(peerVideo.state.position, hostStart));

      expect(
        peerVideo.state.position,
        _closeTo(hostStart),
        reason: "the joining peer must land on the host's existing progress",
      );
      expect(peerVideo.state.status, PlaybackStatus.paused);
      expect(
        hostVideo.state.position,
        _closeTo(hostStart),
        reason: 'and the host must not be dragged anywhere by the joiner',
      );
    },
  );

  test(
    '2b. a peer that connects empty then loads still converges (Check 6)',
    () async {
      final hostVideo = newCore();
      await switchLocalToSynced('host', video: hostVideo, at: hostStart);
      await _until(() => server.roomSetBy == 'host');
      expect(
        server.roomPosition,
        _closeTo(hostStart),
        reason: 'the live switch must have published the host position to the '
            'room before a joiner arrives',
      );

      final peerVideo = newCore();
      await joinThenLoad('peer', video: peerVideo);
      await _until(() => _near(peerVideo.state.position, hostStart));

      expect(
        peerVideo.state.position,
        _closeTo(hostStart),
        reason:
            "the joiner loads after the room's first doSeek, so a FOLLOW "
            'apply=false at 0s is the Debian Check 6 miss: the room position '
            'must still be applied once the file is open',
      );
      expect(peerVideo.state.status, PlaybackStatus.paused);
      expect(
        hostVideo.state.position,
        _closeTo(hostStart),
        reason: 'the host must not be dragged to the joiner\'s load-at-zero',
      );
    },
  );

  test('4. after Local -> Synced the host drives the peer', () async {
    final hostVideo = newCore();
    final peerVideo = newCore();
    await switchLocalToSynced('host', video: hostVideo, at: hostStart);
    await _until(() => server.roomSetBy == 'host');
    await joinSynced('peer', video: peerVideo);
    await _until(() => _near(peerVideo.state.position, hostStart));

    hostVideo.userPlay();
    await _until(() => peerVideo.state.status == PlaybackStatus.playing);
    expect(
      peerVideo.state.status,
      PlaybackStatus.playing,
      reason: 'host -> peer play must propagate after the live switch',
    );

    hostVideo.userPause();
    await _until(() => peerVideo.state.status == PlaybackStatus.paused);
    expect(
      peerVideo.state.status,
      PlaybackStatus.paused,
      reason: 'host -> peer pause must propagate after the live switch',
    );

    const target = Duration(minutes: 12);
    hostVideo.userSeek(target);
    await _until(() => _near(peerVideo.state.position, target));
    expect(
      peerVideo.state.position,
      _closeTo(target),
      reason: 'host -> peer seek must propagate after the live switch',
    );
  });

  test('5. after Local -> Synced the peer still drives the host', () async {
    final hostVideo = newCore();
    final peerVideo = newCore();
    await switchLocalToSynced('host', video: hostVideo, at: hostStart);
    await _until(() => server.roomSetBy == 'host');
    await joinSynced('peer', video: peerVideo);
    await _until(() => _near(peerVideo.state.position, hostStart));

    // The peer has just applied the host's state; let its remote-apply fallout
    // window lapse so the next action reads as the peer's own, as it would for
    // a real viewer reaching for the keyboard.
    await _settleRemote();

    peerVideo.userPlay();
    await _until(() => hostVideo.state.status == PlaybackStatus.playing);
    expect(hostVideo.state.status, PlaybackStatus.playing);

    peerVideo.userPause();
    await _until(() => hostVideo.state.status == PlaybackStatus.paused);
    expect(hostVideo.state.status, PlaybackStatus.paused);

    const target = Duration(minutes: 21);
    peerVideo.userSeek(target);
    await _until(() => _near(hostVideo.state.position, target));
    expect(
      hostVideo.state.position,
      _closeTo(target),
      reason: 'peer -> host seek must still propagate after the live switch',
    );
  });

  test(
    '6. Local -> Synced -> Local -> Synced leaves no stale or duplicate wiring',
    () async {
      final hostVideo = newCore();
      final session = track(SessionServices.local());
      hostVideo.openAt(movie, at: hostStart);
      await pumpEventQueue();

      for (var round = 0; round < 3; round++) {
        session.startSynced(video: hostVideo, openSource: movie);
        await server.dial(session.sync!, name: 'host$round');
        await _until(() => server.roomSetBy == 'host$round');
        expect(
          server.roomSetBy,
          'host$round',
          reason:
              'every re-entry must re-establish the room state (round $round)',
        );
        await session.stopToLocal();
        expect(session.sync, isNull);
        expect(session.bridge, isNull);
        expect(session.chat, isNull);
      }

      // One last live round must still be fully two-way.
      session.startSynced(video: hostVideo, openSource: movie);
      await server.dial(session.sync!, name: 'host-final');
      await _until(() => server.roomSetBy == 'host-final');

      final peerVideo = newCore();
      await joinSynced('peer', video: peerVideo);
      await _until(() => _near(peerVideo.state.position, hostStart));

      hostVideo.userPlay();
      await _until(() => peerVideo.state.status == PlaybackStatus.playing);
      expect(peerVideo.state.status, PlaybackStatus.playing);

      await _settleRemote();
      peerVideo.userPause();
      await _until(() => hostVideo.state.status == PlaybackStatus.paused);
      expect(hostVideo.state.status, PlaybackStatus.paused);

      // Exactly one bridge is listening: a stale bridge from an earlier round
      // would apply the same remote pause again, doubling the command tape.
      expect(
        hostVideo.commands.where((c) => c == 'pause').length,
        1,
        reason: 'a stale bridge from an earlier round would double-apply',
      );
    },
  );

  test('7. a Local-only session never touches the room', () async {
    final hostVideo = newCore();
    final peerVideo = newCore();
    await joinSynced('peer', video: peerVideo, at: hostStart);

    final local = track(SessionServices.local());
    hostVideo.openAt(movie, at: const Duration(minutes: 9), playing: true);
    hostVideo.userPause();
    hostVideo.userSeek(const Duration(minutes: 33));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(local.sync, isNull);
    expect(local.bridge, isNull);
    expect(local.chat, isNull);
    expect(
      server.acceptedChanges,
      isEmpty,
      reason: 'a local session must be invisible to the room',
    );
    expect(server.roomSetBy, isNull);
    expect(
      peerVideo.state.position,
      _closeTo(hostStart),
      reason: 'the local viewer must not move anyone else',
    );
  });
}

/// Poll until [reached] holds. Socket round trips plus the server heartbeat make
/// a fixed delay flaky under load; polling returns as soon as the room converges.
Future<void> _until(
  bool Function() reached, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!reached() && stopwatch.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Outlast `PlaybackSyncBridge`'s remote-apply fallout window
/// (`remoteApplyWindow` + `remoteCommandWait`), during which a state flip is
/// read as late backend fallout from the apply rather than as a fresh local
/// action. Real viewers clear it simply by not hammering the keyboard inside a
/// second of a peer's command.
Future<void> _settleRemote() =>
    Future<void>.delayed(const Duration(milliseconds: 1600));

const _tolerance = Duration(milliseconds: 1500);

bool _near(Duration actual, Duration expected) =>
    (actual - expected).abs() <= _tolerance;

Matcher _closeTo(Duration expected) => predicate<Duration>(
  (actual) => _near(actual, expected),
  'within ${_tolerance.inMilliseconds}ms of ${expected.inSeconds}s',
);
